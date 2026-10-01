[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'naming.ps1')
. (Join-Path $PSScriptRoot 'deployment-context.ps1')

function Invoke-AzureJson {
    param([Parameter(Mandatory)][string[]] $Arguments)
    $json = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure check failed: az $($Arguments -join ' ')" }
    return $json | ConvertFrom-Json -ErrorAction Stop
}

$values = Get-DeploymentEnvironment
$subscription = Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID'
$location = Get-DeploymentValue $values 'AZURE_LOCATION'
$environment = Get-DeploymentValue $values 'AZURE_ENV_NAME'
$subscriptionCode = Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_CODE'
if ($environment -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])$') {
    throw 'AZURE_ENV_NAME must be 2-32 lowercase alphanumeric/hyphen characters, starting and ending alphanumeric.'
}
$profile = Get-DeploymentValue $values 'DEPLOYMENT_PROFILE'
if ($profile -cnotin @('core', 'full')) {
    throw 'This demo supports only DEPLOYMENT_PROFILE=core or full.'
}
$apiCenterSku = Get-DeploymentParameterValue $values 'apiCenterSku'
if ($apiCenterSku -cnotin @('Free', 'Standard')) {
    throw 'API_CENTER_SKU must be Free or Standard.'
}
if (-not [string]::IsNullOrWhiteSpace($values['AZURE_FEATURE_OVERRIDES_JSON']) -and $values.AZURE_FEATURE_OVERRIDES_JSON -ne '{}') {
    throw 'Feature overrides are not supported; choose core or full.'
}
Assert-DeploymentSubscription $subscription
$account = Invoke-AzureJson @('account', 'show', '--subscription', $subscription)
if ($account.state -ne 'Enabled') { throw "Subscription '$subscription' is not enabled." }
$null = Assert-SubscriptionCode -SubscriptionName $account.name -CachedCode $subscriptionCode
$locationCode = Get-LocationCode $location (Get-CoreCatalogPath 'location-codes.json')
$publisherEmail = Get-DeploymentValue $values 'APIM_PUBLISHER_EMAIL'
$null = Get-DeploymentValue $values 'APIM_PUBLISHER_NAME'
if ($publisherEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
    throw 'APIM_PUBLISHER_EMAIL must be a valid email address.'
}

$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'build-catalog.ps1') -Check
$catalog = Get-Content (Join-Path $root 'infra\modules\catalog.json') -Raw | ConvertFrom-Json
$requiredModules = @('api-center', 'api-management', 'app-hosting', 'monitoring', 'foundry', 'managed-redis')
if (@(Compare-Object $requiredModules @($catalog.modules.name)).Count -ne 0) {
    throw 'The module catalog must contain exactly api-center, api-management, app-hosting, monitoring, foundry, and managed-redis.'
}
$activeModules = @($catalog.modules | Where-Object { $profile -in $_.profiles })
$providers = @($activeModules.providers | Sort-Object -Unique)
foreach ($provider in $providers) {
    $details = Invoke-AzureJson @('provider', 'show', '--namespace', $provider, '--subscription', $subscription)
    if ($details.registrationState -ne 'Registered') {
        throw "Register provider '$provider' before provisioning: az provider register --namespace $provider"
    }
    $resourceType = switch ($provider) {
        'Microsoft.ApiCenter' { 'services' }
        'Microsoft.ApiManagement' { 'service' }
        'Microsoft.OperationalInsights' { 'workspaces' }
        'Microsoft.Insights' { 'components' }
        'Microsoft.App' { 'containerApps' }
        'Microsoft.CognitiveServices' { 'accounts' }
        'Microsoft.Cache' { 'redisEnterprise' }
    }
    if ($resourceType) {
        $resourceLocation = switch ($provider) {
            'Microsoft.CognitiveServices' { Get-DeploymentParameterValue $values 'aiLocation' }
            'Microsoft.Cache' { Get-DeploymentParameterValue $values 'cacheLocation' }
            'Microsoft.App' { Get-DeploymentParameterValue $values 'appHostingLocation' }
            default { $location }
        }
        $null = Get-LocationCode $resourceLocation (Get-CoreCatalogPath 'location-codes.json')
        $type = $details.resourceTypes | Where-Object resourceType -EQ $resourceType | Select-Object -First 1
        $supported = @($type.locations | ForEach-Object { ($_ -replace '\s', '').ToLowerInvariant() })
        if ($resourceLocation.ToLowerInvariant() -notin $supported) {
            throw "$provider/$resourceType does not support '$resourceLocation'. Supported regions: $($type.locations -join ', ')"
        }
    }
}

$null = & az apic integration create apim --help
if ($LASTEXITCODE -ne 0) {
    throw 'Install apic-extension 1.2.0b1 or newer with preview support before provisioning.'
}

$expectedGroup = Get-AzName 'rg' $locationCode $subscriptionCode $environment
$exists = & az group exists --name $expectedGroup --subscription $subscription --output tsv
if ($LASTEXITCODE -ne 0) { throw "Unable to check resource group '$expectedGroup'." }
$existingDeployments = @()
if ($exists.Trim() -eq 'true') {
    $group = Invoke-AzureJson @('group', 'show', '--name', $expectedGroup, '--subscription', $subscription)
    if ($group.tags.'azd-env-name' -ne $environment -or
        $group.tags.repository -ne (Get-DeploymentValue $values 'AZURE_REPOSITORY')) {
        throw "Resource group '$expectedGroup' belongs to another environment/repository; refusing to adopt it."
    }
    $apiCenterName = Get-AzName 'apic' $locationCode $subscriptionCode $environment
    $apiCenters = Invoke-AzureJson @('resource', 'list', '--resource-type', 'Microsoft.ApiCenter/services',
        '--resource-group', $expectedGroup, '--subscription', $subscription)
    $existingApiCenter = @($apiCenters | Where-Object name -EQ $apiCenterName)
    if ($existingApiCenter.Count -gt 1 -or
        ($existingApiCenter.Count -eq 1 -and $existingApiCenter[0].sku.name -cnotin @('Free', 'Standard'))) {
        throw "Unable to determine the current plan for API Center '$apiCenterName'; inspect its SKU before provisioning."
    }
    if ($existingApiCenter.Count -eq 1 -and $existingApiCenter[0].sku.name -eq 'Standard' -and $apiCenterSku -eq 'Free') {
        throw "API Center '$apiCenterName' is already Standard; refusing to downgrade it. Run: azd env set API_CENTER_SKU Standard"
    }
    if ($profile -eq 'full' -and $values.Contains('AZURE_AI_FOUNDRY_NAME') -and
        -not [string]::IsNullOrWhiteSpace($values.AZURE_AI_FOUNDRY_NAME)) {
        $accountName = $values.AZURE_AI_FOUNDRY_NAME
        $accountId = "/subscriptions/$subscription/resourceGroups/$expectedGroup/providers/Microsoft.CognitiveServices/accounts/$accountName"
        if ($values.AZURE_AI_FOUNDRY_RESOURCE_ID -ne $accountId) {
            throw 'Foundry outputs do not belong to the selected subscription/resource group. Refresh the azd outputs.'
        }
        $accounts = Invoke-AzureJson @('cognitiveservices', 'account', 'list', '--resource-group', $expectedGroup, '--subscription', $subscription)
        $existingAccount = @($accounts | Where-Object { $_.id -eq $accountId -and
            $_.location -eq (Get-DeploymentParameterValue $values 'aiLocation') })
        if ($existingAccount.Count -eq 1) {
            $existingDeployments = @(Invoke-AzureJson @('cognitiveservices', 'account', 'deployment', 'list',
                '--name', $accountName, '--resource-group', $expectedGroup, '--subscription', $subscription))
        }
    }
}
if ($profile -eq 'full') {
    & (Join-Path $PSScriptRoot 'ai-preflight.ps1') -Values $values -ExistingDeployments $existingDeployments
}
Write-Host "Preflight passed: $environment / $subscriptionCode / $location ($locationCode) / $profile."
