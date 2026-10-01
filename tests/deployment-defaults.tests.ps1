$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\deployment-context.ps1')

function Assert-Default {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-DefaultFailure {
    param([scriptblock] $Action, [string] $Pattern)
    try { $null = & $Action 6>&1 3>&1 }
    catch {
        Assert-Default ($_.Exception.Message -match $Pattern) "Unexpected error: $_"
        return
    }
    throw "Expected error matching '$Pattern'."
}

$global:deploymentDefaultsTestState = @{
    values = @{ AZURE_ENV_NAME = 'defaults-test' }
    subscription = '00000000-0000-0000-0000-000000000001'
    accountExitCode = 0
    failedSetting = ''
    writes = [System.Collections.Generic.List[string]]::new()
    previews = 0
}

function azd {
    Assert-Default ($args -notcontains '--environment') 'Defaults must not override azd environment precedence.'
    $global:LASTEXITCODE = 0
    $state = $global:deploymentDefaultsTestState
    switch ("$($args[0]) $($args[1])") {
        'env list' { ConvertTo-Json -InputObject @(@{ Name = 'defaults-test'; IsDefault = $true }) }
        'env get-values' { $state.values | ConvertTo-Json }
        'env set' {
            if ($args[2] -eq $state.failedSetting) { $global:LASTEXITCODE = 11; return }
            $state.values[$args[2]] = $args[3]
            $state.writes.Add($args[2])
        }
        default {
            if ($args[0] -ne 'provision' -or $args -notcontains '--preview') {
                throw "Unexpected azd invocation: $args"
            }
            $state.previews++
        }
    }
}

function az {
    $global:LASTEXITCODE = 0
    $state = $global:deploymentDefaultsTestState
    switch ("$($args[0]) $($args[1])") {
        'account show' {
            $global:LASTEXITCODE = $state.accountExitCode
            if ($state.accountExitCode -ne 0) { return }
            if ($args -contains 'id') { $state.subscription }
            elseif ($args -contains 'name') { 'example-1' }
            else { @{ name = 'example-1'; state = 'Enabled' } | ConvertTo-Json }
        }
        'provider show' {
            @{
                registrationState = 'Registered'
                resourceTypes = @('services', 'service', 'workspaces', 'components', 'containerApps', 'accounts', 'redisEnterprise') |
                    ForEach-Object { @{ resourceType = $_; locations = @(if ($_ -eq 'containerApps') { 'West US 3' } else { 'East US' }) } }
            } | ConvertTo-Json -Depth 5
        }
        'cognitiveservices model' {
            $models = foreach ($kind in @('chat', 'embedding')) {
                $modelName = Get-DeploymentParameterValue $state.values "${kind}ModelName"
                $skuName = Get-DeploymentParameterValue $state.values "${kind}DeploymentSku"
                @{ kind = 'AIServices'; skuName = 'S0'; model = @{
                    format = 'OpenAI'
                    name = $modelName
                    version = Get-DeploymentParameterValue $state.values "${kind}ModelVersion"
                    capabilities = @{ chatCompletion = 'true' }
                    lifecycleStatus = 'GenerallyAvailable'
                    skus = @(@{
                        name = $skuName
                        usageName = "OpenAI.$skuName.$modelName"
                        capacity = @{ minimum = 1; maximum = 100; step = 1 }
                    })
                } }
            }
            ConvertTo-Json -InputObject $models -Depth 10
        }
        'cognitiveservices usage' {
            @('chat', 'embedding') | ForEach-Object {
                $modelName = Get-DeploymentParameterValue $state.values "${_}ModelName"
                $skuName = Get-DeploymentParameterValue $state.values "${_}DeploymentSku"
                @{ name = @{ value = "OpenAI.$skuName.$modelName" }; limit = 100; currentValue = 0 }
            } | ConvertTo-Json -Depth 5
        }
        'apic integration' { }
        'group exists' { 'false' }
        default { throw "Unexpected Azure CLI invocation: $args" }
    }
}

$savedEnvironment = $env:AZURE_ENV_NAME
try {
    $env:AZURE_ENV_NAME = $null
    $state = $global:deploymentDefaultsTestState
    $bindings = @(Get-DeploymentParameterBindings)
    $log = & (Join-Path $root 'scripts\01-create-service.ps1') -PreviewOnly 6>&1 3>&1
    Assert-Default ($state.previews -eq 1) 'An environment with only its name must reach preview without provisioning.'
    Assert-Default ("$log" -match "Initialized AZURE_LOCATION: 'eastus'.*source:") 'Initialized defaults must report their source.'
    Assert-Default ("$log" -match 'demo placeholder') 'The demo publisher email must be clearly labeled.'
    Assert-Default ($state.values.AZURE_SUBSCRIPTION_ID -eq $state.subscription) 'Missing subscription must use the active Azure CLI subscription.'
    Assert-Default ($state.values.AZURE_LOCATION -eq 'eastus' -and
        $state.values.AI_LOCATION -eq 'eastus' -and $state.values.CACHE_LOCATION -eq 'eastus') 'Dependent regions must follow the initialized location.'
    Assert-Default ($state.values.APIM_PUBLISHER_NAME -eq 'API Center Demo' -and
        $state.values.APIM_PUBLISHER_EMAIL -eq 'api-team@example.com') 'Publisher defaults changed.'
    foreach ($binding in $bindings) {
        $value = Get-DeploymentParameterValue $state.values $binding.ParameterName
        if ($binding.HasDefault) {
            Assert-Default ($value -ceq $binding.DefaultValue) "Default drifted for $($binding.ParameterName)."
        }
        else {
            Assert-Default (-not [string]::IsNullOrWhiteSpace($value)) "Required parameter $($binding.ParameterName) remains unset."
        }
    }
    Assert-DefaultFailure { Get-DeploymentValue $state.values 'APIM_SERVICE' } 'Missing azd value'
    Assert-DefaultFailure { Get-DeploymentParameterValue @{} 'unknown' } 'Unknown deployment parameter'

    $original = $state.values.Clone()
    $state.writes.Clear()
    $null = & (Join-Path $root 'scripts\set-deployment-tags.ps1') 6>&1 3>&1
    Assert-Default (($state.writes -join ',') -eq 'AZURE_LAST_UPDATED_ON') 'Reruns must only update the last-updated timestamp.'
    Assert-Default ($state.values.AZURE_CREATED_ON -ceq $original.AZURE_CREATED_ON) 'Reruns must preserve the creation timestamp.'

    $state.values = @{ AZURE_ENV_NAME = 'defaults-test' }
    foreach ($binding in $bindings | Where-Object EnvironmentName -NE 'AZURE_ENV_NAME') {
        $state.values[$binding.EnvironmentName] = ' '
    }
    $state.values.AZURE_SUBSCRIPTION_ID = ''
    $state.values.AZURE_FEATURE_OVERRIDES_JSON = ''
    $null = & (Join-Path $root 'scripts\01-create-service.ps1') -PreviewOnly 6>&1 3>&1
    Assert-Default ($state.previews -eq 2) 'Blank defaultable settings must reach preview.'
    foreach ($binding in $bindings | Where-Object { $_.HasDefault -and $_.DefaultValue -ne '' }) {
        Assert-Default ($state.values[$binding.EnvironmentName] -ceq $binding.DefaultValue) "Blank $($binding.EnvironmentName) was not initialized."
    }

    $state.values = $original.Clone()
    $overrides = @{
        AZURE_LOCATION = 'westus3'; AI_LOCATION = 'eastus2'; CACHE_LOCATION = 'westus2'
        DEPLOYMENT_PROFILE = 'core'; APIM_PUBLISHER_NAME = 'Custom Team'; APIM_PUBLISHER_EMAIL = 'custom@example.org'
        API_CENTER_SKU = 'Standard'
        CHAT_MODEL_NAME = 'custom-model'; CHAT_CAPACITY = '20'; REDIS_HIGH_AVAILABILITY = 'true'
        AZURE_OWNER = 'demo-team'; AZURE_REPOSITORY = 'custom/repository'
    }
    foreach ($key in $overrides.Keys) { $state.values[$key] = $overrides[$key] }
    $state.writes.Clear()
    $null = & (Join-Path $root 'scripts\set-deployment-tags.ps1') 6>&1 3>&1
    Assert-Default (($state.writes -join ',') -eq 'AZURE_LAST_UPDATED_ON') 'Explicit settings must not be rewritten.'
    foreach ($key in $overrides.Keys) {
        Assert-Default ($state.values[$key] -ceq $overrides[$key]) "Explicit $key was overwritten."
    }
    $state.values.Remove('AI_LOCATION')
    $state.values.CACHE_LOCATION = ''
    $null = & (Join-Path $root 'scripts\set-deployment-tags.ps1') 6>&1 3>&1
    Assert-Default ($state.values.AI_LOCATION -eq 'westus3' -and $state.values.CACHE_LOCATION -eq 'westus3') 'Missing dependent regions must follow an explicit location.'

    $state.values = @{ AZURE_ENV_NAME = 'defaults-test' }
    $state.writes.Clear()
    $state.accountExitCode = 1
    Assert-DefaultFailure { & (Join-Path $root 'scripts\01-create-service.ps1') -PreviewOnly } 'Run az login'
    Assert-Default ($state.writes.Count -eq 0 -and $state.previews -eq 2) 'Missing login must stop initialization and preview.'
    $state.accountExitCode = 0
    $state.failedSetting = 'AZURE_LOCATION'
    Assert-DefaultFailure { & (Join-Path $root 'scripts\01-create-service.ps1') -PreviewOnly } "Unable to set azd environment value 'AZURE_LOCATION'"
    Assert-Default (-not $state.values.ContainsKey('AZURE_LOCATION') -and $state.previews -eq 2) 'A failed default write must not appear successful or continue to preview.'
    $state.failedSetting = ''
    $state.values = $original.Clone()
    $state.values.AZURE_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000099'
    Assert-DefaultFailure { & (Join-Path $root 'scripts\01-create-service.ps1') -PreviewOnly } 'subscriptions differ'
    Assert-Default ($state.values.AZURE_SUBSCRIPTION_ID.EndsWith('99')) 'An explicit subscription must never be silently replaced.'
    Assert-Default ($state.previews -eq 2) 'A subscription mismatch must block preview.'
}
finally {
    $env:AZURE_ENV_NAME = $savedEnvironment
    Remove-Variable deploymentDefaultsTestState -Scope Global
}
Write-Host 'Deployment defaults checks passed.'
