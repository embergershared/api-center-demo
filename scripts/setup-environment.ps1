[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deployment-context.ps1')
. (Join-Path $PSScriptRoot 'naming.ps1')

$subscriptionId = '4c88693f-5cc9-4f30-9d1e-d58d4221cf25'
$location = 'centralus'
$environmentName = 'apic-demo'
$appHostingLocation = 'westus3'
$publisherName = 'API Center Demo'
$publisherEmail = 'apicenter-admin@apic-demo.dev'

function Read-SetupValue {
    param([string] $Label, [string] $Default = '', [string] $SavedValue = '')

    if (-not [string]::IsNullOrWhiteSpace($SavedValue)) { $Default = $SavedValue }
    $prompt = if ($Default) { "$Label [$Default]" } else { $Label }
    $value = (Read-Host $prompt).Trim()
    if (-not $value) { $value = $Default }
    if (-not $value) { throw "$Label is required." }
    return $value
}

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $environmentName = Read-SetupValue 'azd environment name (new or existing)' $environmentName
    if ($environmentName -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])$') {
        throw 'Environment name must be 2-32 lowercase alphanumeric/hyphen characters, starting and ending alphanumeric.'
    }

    $json = & azd env list --output json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list azd environments.' }
    $environments = ($json -join [Environment]::NewLine) | ConvertFrom-Json
    $environmentExists = @($environments | Where-Object Name -EQ $environmentName).Count -gt 0
    $existing = @{}
    if ($environmentExists) {
        $existing = Get-DeploymentEnvironment -EnvironmentName $environmentName
        if ((Get-DeploymentValue $existing 'AZURE_ENV_NAME') -cne $environmentName) {
            throw 'The loaded azd environment does not match the requested environment.'
        }
        Write-Host "Reusing environment '$environmentName'; press Enter to keep each saved value."
    }

    $subscriptionId = Read-SetupValue 'Azure subscription ID' $subscriptionId $existing.AZURE_SUBSCRIPTION_ID
    $parsedId = [guid]::Empty
    if (-not [guid]::TryParse($subscriptionId, [ref]$parsedId)) {
        throw 'Azure subscription ID must be a GUID.'
    }
    $location = (Read-SetupValue 'Azure location' $location $existing.AZURE_LOCATION).ToLowerInvariant()
    $null = Get-LocationCode $location (Get-CoreCatalogPath 'location-codes.json')

    $settings = [ordered]@{
        AZURE_SUBSCRIPTION_ID = $subscriptionId
        AZURE_LOCATION = $location
        APP_HOSTING_LOCATION = (Read-SetupValue 'App hosting location' $appHostingLocation $existing.APP_HOSTING_LOCATION).ToLowerInvariant()
        AI_LOCATION = (Read-SetupValue 'AI location' $location $existing.AI_LOCATION).ToLowerInvariant()
        CACHE_LOCATION = (Read-SetupValue 'Cache location' $location $existing.CACHE_LOCATION).ToLowerInvariant()
        APIM_PUBLISHER_NAME = Read-SetupValue 'APIM publisher name' $publisherName $existing.APIM_PUBLISHER_NAME
        APIM_PUBLISHER_EMAIL = Read-SetupValue 'APIM publisher email' $publisherEmail $existing.APIM_PUBLISHER_EMAIL
    }
    foreach ($key in @('APP_HOSTING_LOCATION', 'AI_LOCATION', 'CACHE_LOCATION')) {
        $null = Get-LocationCode $settings[$key] (Get-CoreCatalogPath 'location-codes.json')
    }
    if ($settings.APIM_PUBLISHER_EMAIL -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        throw 'APIM publisher email must be a valid email address.'
    }

    $json = & az account show --subscription $subscriptionId --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the subscription. Run az login and verify the subscription ID.' }
    $account = ($json -join [Environment]::NewLine) | ConvertFrom-Json
    if ($account.state -ne 'Enabled') { throw "Subscription '$subscriptionId' is not enabled." }
    $null = Get-SubscriptionCode $account.name

    # The selected environment must not inherit process overrides from a previous demo.
    $overrideNames = @('AZURE_SUBSCRIPTION_ID') + @(Get-DeploymentParameterBindings | ForEach-Object EnvironmentName)
    foreach ($key in $overrideNames | Sort-Object -Unique) {
        if ($null -ne [Environment]::GetEnvironmentVariable($key, 'Process')) {
            Write-Host "Clearing process override '$key'; configuration will come from azd."
            [Environment]::SetEnvironmentVariable($key, $null, 'Process')
        }
    }

    & az account set --subscription $subscriptionId
    if ($LASTEXITCODE -ne 0) { throw "Unable to select Azure subscription '$subscriptionId'." }
    if (-not $environmentExists) {
        & azd env new $environmentName --subscription $subscriptionId --location $location --no-prompt
        if ($LASTEXITCODE -ne 0) { throw "Unable to create azd environment '$environmentName'." }
    }
    & azd env select $environmentName
    if ($LASTEXITCODE -ne 0) { throw "Unable to select azd environment '$environmentName'." }

    foreach ($key in $settings.Keys) {
        if ($existing[$key] -cne $settings[$key]) {
            & azd env set $key $settings[$key] --environment $environmentName
            if ($LASTEXITCODE -ne 0) { throw "Unable to save '$key' in azd environment '$environmentName'." }
        }
    }
    & (Join-Path $PSScriptRoot 'set-deployment-tags.ps1')
    $saved = Get-DeploymentEnvironment
    foreach ($key in $settings.Keys) {
        if ((Get-DeploymentValue $saved $key) -cne $settings[$key]) {
            throw "Saved azd value '$key' does not match the requested value."
        }
    }
    if ((Get-DeploymentValue $saved 'AZURE_ENV_NAME') -cne $environmentName) {
        throw 'The selected azd environment does not match the requested environment.'
    }
    Write-Host "Environment '$environmentName' configured. No Azure resources were provisioned."
}
finally {
    Pop-Location
}
