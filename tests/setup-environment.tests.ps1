$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\deployment-context.ps1')

function Assert-Setup {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function New-SetupTestState {
    param([string] $Location = '', [string] $EnvironmentName = 'setup-test')
    $global:setupTestState = @{
        answers = [System.Collections.Generic.Queue[string]]::new()
        calls = [System.Collections.Generic.List[string]]::new()
        prompts = [System.Collections.Generic.List[string]]::new()
        values = @{}
        environments = @()
        selected = ''
        subscription = '00000000-0000-0000-0000-000000000001'
        accountName = 'demo-3'
        accountState = 'Enabled'
        failCommand = ''
        corruptRead = $false
    }
    foreach ($answer in @($EnvironmentName, $global:setupTestState.subscription, $Location,
        '', '', '', 'Demo Team', 'demo@example.org')) {
        $global:setupTestState.answers.Enqueue($answer)
    }
}

function Read-Host {
    param([string] $Prompt)
    Assert-Setup ($global:setupTestState.answers.Count -gt 0) "Unexpected prompt: $Prompt"
    $global:setupTestState.prompts.Add($Prompt)
    $global:setupTestState.answers.Dequeue()
}

function az {
    $state = $global:setupTestState
    $command = "az $($args -join ' ')"
    $state.calls.Add($command)
    $global:LASTEXITCODE = 0
    if ($state.failCommand -and $command.StartsWith($state.failCommand)) {
        $global:LASTEXITCODE = 17
        return
    }
    switch ("$($args[0]) $($args[1])") {
        'account show' {
            if ($args -contains 'id') { $state.subscription }
            elseif ($args -contains 'name') { $state.accountName }
            else { @{ id = $state.subscription; name = $state.accountName; state = $state.accountState } | ConvertTo-Json }
        }
        'account set' {
            Assert-Setup ($args[2] -eq '--subscription' -and $args[3] -eq $state.subscription) 'Wrong Azure subscription selected.'
        }
        default { throw "Unexpected Azure CLI call: $args" }
    }
}

function azd {
    $state = $global:setupTestState
    $command = "azd $($args -join ' ')"
    $state.calls.Add($command)
    $global:LASTEXITCODE = 0
    if ($state.failCommand -and $command.StartsWith($state.failCommand)) {
        $global:LASTEXITCODE = 17
        return
    }
    switch ("$($args[0]) $($args[1])") {
        'env list' { ConvertTo-Json -InputObject @($state.environments) }
        'env new' {
            Assert-Setup ([string]::IsNullOrEmpty($env:AZURE_ENV_NAME) -and
                [string]::IsNullOrEmpty($env:AZURE_LOCATION) -and
                [string]::IsNullOrEmpty($env:AZURE_SUBSCRIPTION_ID) -and
                [string]::IsNullOrEmpty($env:CHAT_CAPACITY)) 'Stale process overrides must be cleared before creating the environment.'
            Assert-Setup ($args -contains '--no-prompt' -and $args -contains '--subscription' -and
                $args -contains '--location') 'Environment creation must receive the prompted inputs noninteractively.'
            $state.values = @{ AZURE_ENV_NAME = $args[2] }
            $state.environments = @(@{ Name = $args[2]; IsDefault = $true })
        }
        'env select' {
            $state.selected = $args[2]
            Assert-Setup ($state.selected -eq $state.values.AZURE_ENV_NAME) 'Wrong environment selected.'
            foreach ($environment in $state.environments) {
                $environment.IsDefault = $environment.Name -eq $state.selected
            }
        }
        'env set' {
            Assert-Setup ($state.selected -eq $state.values.AZURE_ENV_NAME) 'Settings written before selecting the new environment.'
            $environmentIndex = [array]::IndexOf($args, '--environment')
            if ($environmentIndex -ge 0) {
                Assert-Setup ($args[$environmentIndex + 1] -eq $state.selected) 'Settings explicitly target the wrong environment.'
            }
            $state.values[$args[2]] = $args[3]
        }
        'env get-values' {
            $environmentIndex = [array]::IndexOf($args, '--environment')
            if ($environmentIndex -ge 0) {
                Assert-Setup ($args[$environmentIndex + 1] -eq $state.values.AZURE_ENV_NAME) 'Existing settings must be loaded from the requested environment.'
            }
            else {
                Assert-Setup ($state.selected -eq $state.values.AZURE_ENV_NAME -and
                    [string]::IsNullOrEmpty($env:AZURE_ENV_NAME)) 'Implicit reads must use the selected environment without a stale override.'
            }
            $values = $state.values.Clone()
            if ($state.corruptRead) { $values.AZURE_LOCATION = 'wrong-region' }
            $values | ConvertTo-Json
        }
        default { throw "Unexpected azd call (setup must not deploy): $args" }
    }
}

function Invoke-SetupTest {
    & (Join-Path $root 'scripts\setup-environment.ps1') 6>&1 3>&1
}

function Assert-SetupFailure {
    param([string] $Pattern)
    try { $null = Invoke-SetupTest }
    catch {
        Assert-Setup ($_.Exception.Message -match $Pattern) "Unexpected setup error: $_"
        return
    }
    throw "Expected setup failure matching '$Pattern'."
}

$outputNames = @('AZURE_RESOURCE_GROUP', 'APIC_SERVICE', 'APIC_RESOURCE_ID', 'APIC_PRINCIPAL_ID',
    'APIC_LOCATION', 'APIM_SERVICE', 'APIM_RESOURCE_ID', 'APIM_GATEWAY_URL',
    'GRID_API_APP_URL', 'GRID_API_APP_NAME', 'GRID_MCP_APP_URL', 'GRID_MCP_APP_NAME')
$savedProcess = @{}
$processNames = @('AZURE_SUBSCRIPTION_ID', 'RESOURCE_GROUP', 'APIM_RESOURCE_GROUP', 'LOCATION',
    'API_ID', 'API_TITLE', 'ENV_DEV', 'ENV_TEST', 'ENV_PROD') + $outputNames +
    @(Get-DeploymentParameterBindings | ForEach-Object EnvironmentName)
foreach ($key in $processNames | Sort-Object -Unique) {
    $savedProcess[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
$originalLocation = Get-Location
try {
    New-SetupTestState
    $env:AZURE_ENV_NAME = 'previous-demo'
    $env:AZURE_SUBSCRIPTION_ID = 'previous-subscription'
    $env:AZURE_LOCATION = 'westus'
    $env:CHAT_CAPACITY = '999'
    Push-Location $PSScriptRoot
    try { $log = Invoke-SetupTest }
    finally { Pop-Location }
    $state = $global:setupTestState
    Assert-Setup ($state.answers.Count -eq 0) 'Setup did not collect all inputs.'
    Assert-Setup ($state.prompts[0] -eq 'azd environment name (new or existing) [apic-demo]') 'Environment name must be the first prompt.'
    Assert-Setup ("$log" -match "Environment 'setup-test' configured" -and "$log" -match 'No Azure resources were provisioned') 'Successful setup must report configuration, not deployment.'
    Assert-Setup ($state.values.AZURE_SUBSCRIPTION_ID -eq $state.subscription -and
        $state.values.AZURE_LOCATION -eq 'centralus' -and $state.values.AI_LOCATION -eq 'centralus' -and
        $state.values.CACHE_LOCATION -eq 'centralus' -and $state.values.APP_HOSTING_LOCATION -eq 'westus3') 'Prompt defaults did not persist in azd.'
    Assert-Setup ($state.values.APIM_PUBLISHER_NAME -eq 'Demo Team' -and
        $state.values.APIM_PUBLISHER_EMAIL -eq 'demo@example.org') 'Publisher input was not persisted.'
    Assert-Setup ($state.values.DEPLOYMENT_PROFILE -eq 'full' -and $state.values.API_CENTER_SKU -eq 'Standard' -and
        $state.values.AZURE_SUBSCRIPTION_CODE -eq 's3' -and $state.values.CHAT_CAPACITY -eq '10') 'Shared defaults/tags must initialize the fresh environment without stale process values.'
    Assert-Setup ($state.calls -contains "azd env new setup-test --subscription $($state.subscription) --location centralus --no-prompt") 'Creation must use the prompted subscription and location.'

    New-SetupTestState
    $state = $global:setupTestState
    $state.subscription = '4c88693f-5cc9-4f30-9d1e-d58d4221cf25'
    $state.answers.Clear()
    1..8 | ForEach-Object { $state.answers.Enqueue('') }
    $null = Invoke-SetupTest
    $expectedDefaults = [ordered]@{
        AZURE_ENV_NAME = 'apic-demo'
        AZURE_SUBSCRIPTION_ID = '4c88693f-5cc9-4f30-9d1e-d58d4221cf25'
        AZURE_LOCATION = 'centralus'
        APP_HOSTING_LOCATION = 'westus3'
        AI_LOCATION = 'centralus'
        CACHE_LOCATION = 'centralus'
        APIM_PUBLISHER_NAME = 'API Center Demo'
        APIM_PUBLISHER_EMAIL = 'apicenter-admin@apic-demo.dev'
    }
    $index = 0
    foreach ($key in $expectedDefaults.Keys) {
        Assert-Setup ($state.values[$key] -ceq $expectedDefaults[$key]) "Enter did not accept the default for '$key'."
        Assert-Setup ($state.prompts[$index].EndsWith("[$($expectedDefaults[$key])]")) "Default for '$key' was not displayed in the prompt."
        $index++
    }

    foreach ($region in @('centralus', 'eastus2')) {
        New-SetupTestState -Location $region
        $null = Invoke-SetupTest
        $state = $global:setupTestState
        Assert-Setup ($state.values.AZURE_LOCATION -eq $region -and $state.values.AI_LOCATION -eq $region -and
            $state.values.CACHE_LOCATION -eq $region) 'Dependent locations must follow the chosen region.'
    }

    New-SetupTestState
    $state = $global:setupTestState
    $state.answers.Clear()
    foreach ($answer in @('other-demo', $state.subscription, 'centralus',
        'westus2', 'eastus2', 'eastus', '', 'owner@example.org')) {
        $state.answers.Enqueue($answer)
    }
    $null = Invoke-SetupTest
    Assert-Setup ($state.values.APP_HOSTING_LOCATION -eq 'westus2' -and
        $state.values.AI_LOCATION -eq 'eastus2' -and $state.values.CACHE_LOCATION -eq 'eastus' -and
        $state.values.APIM_PUBLISHER_NAME -eq 'API Center Demo') 'Explicit service regions or shared publisher default were lost.'
    foreach ($key in $outputNames) { $state.values[$key] = "saved-$key" }
    $state.values.APIC_LOCATION = $state.values.AZURE_LOCATION
    $null = & {
        . (Join-Path $root 'scripts\00-vars.ps1')
        Assert-Setup ($env:GRID_API_APP_URL -eq 'saved-GRID_API_APP_URL' -and
            $env:AZURE_SUBSCRIPTION_ID -eq $state.subscription -and
            $env:LOCATION -eq 'centralus' -and $deploymentEnvironmentName -eq 'other-demo') 'Existing scripts must consume the persisted environment and outputs.'
        Assert-Setup ([string]::IsNullOrEmpty($env:AZURE_ENV_NAME)) 'Loading outputs must not pin a process-level environment.'
    } 6>&1

    $state.values.DEPLOYMENT_PROFILE = 'core'
    $state.values.CHAT_CAPACITY = '25'
    $state.values.CUSTOM_SETTING = 'retain-me'
    $snapshot = $state.values.Clone()
    $state.calls.Clear()
    $state.prompts.Clear()
    $state.answers.Enqueue('other-demo')
    1..7 | ForEach-Object { $state.answers.Enqueue('') }
    $state.selected = 'unrelated-demo'
    $state.environments = @(
        @{ Name = 'unrelated-demo'; IsDefault = $true }
        @{ Name = 'other-demo'; IsDefault = $false }
    )
    $env:AZURE_ENV_NAME = 'unrelated-demo'
    $env:AZURE_LOCATION = 'westus'
    $log = Invoke-SetupTest
    Assert-Setup ("$log" -match "Reusing environment 'other-demo'") 'Reruns must report that the environment is reused.'
    Assert-Setup ($state.calls -contains 'azd env get-values --environment other-demo --output json') 'Saved defaults must come from the named environment, not the process override or project default.'
    Assert-Setup (-not ($state.calls -match '^azd env new')) 'Reruns must not recreate environments.'
    Assert-Setup ($state.selected -eq 'other-demo' -and [string]::IsNullOrEmpty($env:AZURE_ENV_NAME)) 'Reruns must select the requested environment and clear stale overrides.'
    foreach ($key in $snapshot.Keys | Where-Object { $_ -ne 'AZURE_LAST_UPDATED_ON' }) {
        Assert-Setup ($state.values[$key] -ceq $snapshot[$key]) "Rerun changed existing setting/output '$key'."
    }
    $writes = @($state.calls | Where-Object { $_ -match '^azd env set ' })
    Assert-Setup ($writes.Count -eq 1 -and $writes[0] -match '^azd env set AZURE_LAST_UPDATED_ON ') 'Unchanged reruns must only refresh the last-updated tag.'
    $promptKeys = @('AZURE_SUBSCRIPTION_ID', 'AZURE_LOCATION', 'APP_HOSTING_LOCATION',
        'AI_LOCATION', 'CACHE_LOCATION', 'APIM_PUBLISHER_NAME', 'APIM_PUBLISHER_EMAIL')
    for ($index = 0; $index -lt $promptKeys.Count; $index++) {
        Assert-Setup ($state.prompts[$index + 1].EndsWith("[$($snapshot[$promptKeys[$index]])]")) 'Rerun prompts must display saved defaults.'
    }

    $state.calls.Clear()
    $state.answers.Enqueue('other-demo')
    1..6 | ForEach-Object { $state.answers.Enqueue('') }
    $state.answers.Enqueue('updated@example.org')
    $null = Invoke-SetupTest
    Assert-Setup ($state.values.APIM_PUBLISHER_EMAIL -eq 'updated@example.org') 'Explicit changes must be saved on reruns.'
    $writes = @($state.calls | Where-Object { $_ -match '^azd env set ' })
    Assert-Setup ($writes.Count -eq 2 -and
        $writes[0] -eq 'azd env set APIM_PUBLISHER_EMAIL updated@example.org --environment other-demo' -and
        $writes[1] -match '^azd env set AZURE_LAST_UPDATED_ON ') 'Reruns must write only changed settings and the last-updated tag.'

    foreach ($case in @(
        @{ location = ''; name = 'UPPER'; pattern = 'Environment name must' }
        @{ location = ''; name = 'x'; pattern = 'Environment name must' }
        @{ location = ''; name = '-x'; pattern = 'Environment name must' }
        @{ location = 'not-a-region'; name = 'valid-name'; pattern = 'no approved code' }
    )) {
        New-SetupTestState -Location $case.location -EnvironmentName $case.name
        Assert-SetupFailure $case.pattern
        Assert-Setup (-not ($global:setupTestState.calls | Where-Object { $_ -ne 'azd env list --output json' })) 'Invalid core input must fail before reading or changing account/environment state.'
    }

    New-SetupTestState
    $state = $global:setupTestState
    $state.answers.Clear()
    $state.answers.Enqueue('setup-test')
    $state.answers.Enqueue('not-a-guid')
    Assert-SetupFailure 'must be a GUID'
    Assert-Setup ($state.calls.Count -eq 1) 'Invalid subscription must fail before changing account/environment state.'

    New-SetupTestState
    $state = $global:setupTestState
    $state.environments = @(@{ Name = 'setup-test'; IsDefault = $false })
    $state.values = @{ AZURE_ENV_NAME = 'setup-test'; APIM_PUBLISHER_NAME = ' '; CUSTOM_SETTING = 'retain-me' }
    $null = Invoke-SetupTest
    Assert-Setup (-not ($state.calls -match '^azd env new') -and
        $state.values.AZURE_SUBSCRIPTION_ID -eq $state.subscription -and
        $state.values.APIM_PUBLISHER_NAME -eq 'Demo Team' -and $state.values.CUSTOM_SETTING -eq 'retain-me') 'Partially configured environments must be repaired without recreating them or removing unrelated settings.'

    New-SetupTestState
    $state = $global:setupTestState
    $state.failCommand = 'azd env set AZURE_LOCATION'
    Assert-SetupFailure "Unable to save 'AZURE_LOCATION'"
    $state.failCommand = ''
    $state.calls.Clear()
    $state.answers.Enqueue('setup-test')
    1..7 | ForEach-Object { $state.answers.Enqueue('') }
    $null = Invoke-SetupTest
    Assert-Setup (-not ($state.calls -match '^azd env new') -and
        $state.values.AZURE_LOCATION -eq 'centralus' -and $state.values.DEPLOYMENT_PROFILE -eq 'full') 'A retry after a failed write must complete the existing partial environment.'

    New-SetupTestState
    $state = $global:setupTestState
    $state.environments = @(@{ Name = 'setup-test'; IsDefault = $false })
    $state.values = @{ AZURE_ENV_NAME = 'setup-test' }
    $state.failCommand = 'azd env get-values'
    Assert-SetupFailure 'Unable to load the selected'
    Assert-Setup ($state.calls.Count -eq 2) 'A failed existing-environment read must stop before any writes.'

    foreach ($case in @(
        @{ hosting = 'unknown-region'; email = 'demo@example.org'; pattern = 'no approved code' }
        @{ hosting = ''; email = 'not-an-email'; pattern = 'valid email address' }
    )) {
        New-SetupTestState
        $state = $global:setupTestState
        $state.answers.Clear()
        foreach ($answer in @('setup-test', $state.subscription, '', $case.hosting, '', '', '', $case.email)) {
            $state.answers.Enqueue($answer)
        }
        Assert-SetupFailure $case.pattern
        Assert-Setup ($state.calls.Count -eq 1) 'Invalid optional input must fail before changing Azure or azd state.'
    }

    foreach ($case in @(
        @{ command = 'azd env list'; pattern = 'Unable to list' }
        @{ command = 'az account show'; pattern = 'Unable to read the subscription' }
        @{ command = 'az account set'; pattern = 'Unable to select Azure subscription' }
        @{ command = 'azd env new'; pattern = 'Unable to create' }
        @{ command = 'azd env select'; pattern = 'Unable to select azd' }
        @{ command = 'azd env set AZURE_LOCATION'; pattern = "Unable to save 'AZURE_LOCATION'" }
        @{ command = 'azd env set CHAT_CAPACITY'; pattern = "Unable to set azd environment value 'CHAT_CAPACITY'" }
        @{ command = 'azd env get-values'; pattern = 'Unable to load the selected' }
    )) {
        New-SetupTestState
        $state = $global:setupTestState
        $state.failCommand = $case.command
        Assert-SetupFailure $case.pattern
        Assert-Setup ($state.calls[-1].StartsWith($case.command)) 'Setup continued after a failed CLI command.'
    }

    New-SetupTestState
    $global:setupTestState.corruptRead = $true
    Assert-SetupFailure "Saved azd value 'AZURE_LOCATION'"
    New-SetupTestState
    $global:setupTestState.accountName = 'missing-suffix'
    Assert-SetupFailure 'hyphen-delimited'
    Assert-Setup (-not ($global:setupTestState.calls -match '^azd env new')) 'Invalid subscription naming must block creation.'
    New-SetupTestState
    $global:setupTestState.accountState = 'Disabled'
    Assert-SetupFailure 'not enabled'
    Assert-Setup ((Get-Location).Path -eq $originalLocation.Path) 'Setup must restore the working directory after failure.'
}
finally {
    foreach ($key in $savedProcess.Keys) {
        [Environment]::SetEnvironmentVariable($key, $savedProcess[$key], 'Process')
    }
    Remove-Variable setupTestState -Scope Global
}
Write-Host 'Interactive environment setup checks passed.'
