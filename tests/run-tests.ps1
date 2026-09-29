$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\naming.ps1')

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock] $Action, [string] $Pattern)
    try { & $Action }
    catch {
        Assert-True ($_.Exception.Message -match $Pattern) "Unexpected error: $_"
        return
    }
    throw "Expected error matching '$Pattern'."
}

& (Join-Path $PSScriptRoot 'deployment-defaults.tests.ps1')

foreach ($folder in @('scripts', 'tests')) {
    Get-ChildItem (Join-Path $root $folder) -Filter *.ps1 -Recurse | ForEach-Object {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
        Assert-True ($errors.Count -eq 0) "PowerShell syntax errors in $($_.FullName): $errors"
    }
}
& (Join-Path $root 'scripts\build-catalog.ps1') -Check
Get-ChildItem (Join-Path $root 'infra') -Filter *.json -Recurse | ForEach-Object {
    $null = Get-Content $_.FullName -Raw | ConvertFrom-Json
}

$json = & az bicep build --file (Join-Path $root 'infra\main.bicep') --stdout
Assert-True ($LASTEXITCODE -eq 0) 'Bicep build failed.'
$template = $json | ConvertFrom-Json -AsHashtable
$lint = & az bicep lint --file (Join-Path $root 'infra\main.bicep') 2>&1
Assert-True ($LASTEXITCODE -eq 0 -and "$lint" -notmatch '\b(Warning|Error)\b') "Bicep lint failed: $lint"
$resources = $template.resources
Assert-True ($resources.resourceGroup.type -eq 'Microsoft.Resources/resourceGroups') 'Missing resource group.'
Assert-True ($resources.resourceGroup.tags -eq "[variables('tags')]") 'Resource group must use common tags.'
Assert-True (($template.parameters.deploymentProfile.allowedValues -join ',') -eq 'core,full' -and
    $template.parameters.deploymentProfile.defaultValue -eq 'full') 'Full must be the default; core remains available.'

$allTypes = @($resources.resourceGroup.type)
foreach ($moduleName in @('apiCenter', 'apiManagement', 'monitoring')) {
    $module = $resources[$moduleName]
    Assert-True ($module.resourceGroup -eq "[variables('resourceGroupName')]") 'Module is not scoped to the demo group.'
    Assert-True ($module.properties.parameters.tags.value -eq "[variables('tags')]") 'Module lost common tags.'
    foreach ($resource in $module.properties.template.resources) {
        $allTypes += $resource.type
        if ($resource.type -ne 'Microsoft.Authorization/roleAssignments') {
            Assert-True ($resource.tags -eq "[parameters('tags')]") "Tags missing from $($resource.type)."
        }
    }
}
Assert-True (@($allTypes | Where-Object { $_ -match '^Microsoft\.(Network|Compute|Storage|KeyVault)/' }).Count -eq 0) 'Core deployed unwanted infrastructure.'
$apic = @($resources.apiCenter.properties.template.resources | Where-Object type -EQ 'Microsoft.ApiCenter/services')[0]
Assert-True ($apic.identity.type -eq 'SystemAssigned') 'API Center needs managed identity.'
Assert-True ($apic.sku.name -eq "[parameters('skuName')]" -and
    $resources.apiCenter.properties.parameters.skuName.value -eq "[parameters('apiCenterSku')]") 'API Center must receive an explicit SKU on create and update.'
Assert-True ($template.parameters.apiCenterSku.defaultValue -eq 'Free' -and
    ($template.parameters.apiCenterSku.allowedValues -join ',') -eq 'Free,Standard' -and
    $resources.apiCenter.properties.template.parameters.skuName.defaultValue -eq 'Free' -and
    ($resources.apiCenter.properties.template.parameters.skuName.allowedValues -join ',') -eq 'Free,Standard') 'API Center must default to Free and allow explicit Standard preservation.'
$apim = @($resources.apiManagement.properties.template.resources | Where-Object type -EQ 'Microsoft.ApiManagement/service')[0]
Assert-True ($apim.sku.name -eq 'StandardV2' -and $apim.sku.capacity -eq 1) 'APIM must use Standard v2 with one capacity unit.'
$rbac = @($resources.apiManagement.properties.template.resources | Where-Object type -EQ 'Microsoft.Authorization/roleAssignments')[0]
Assert-True ($rbac.properties.principalType -eq 'ServicePrincipal') 'RBAC principal type must be explicit.'
Assert-True ($rbac.scope -match 'Microsoft.ApiManagement/service') 'Reader role must be scoped to APIM.'
Assert-True ($rbac.name -match 'guid\(') 'Role assignment must have a deterministic name.'
Assert-True ($resources.apiManagement.properties.template.variables.readerRoleId -match '71522526-b88f-4d52-b57f-d31fc3546d0d') 'Wrong reader role.'
foreach ($output in @('AZURE_RESOURCE_GROUP','APIC_SERVICE','APIC_RESOURCE_ID','APIC_PRINCIPAL_ID',
    'APIC_LOCATION','APIM_SERVICE','APIM_RESOURCE_ID','APIM_GATEWAY_URL')) {
    Assert-True ($template.outputs.ContainsKey($output)) "Missing output: $output"
}

$rules = Get-Content (Join-Path $root 'infra\core\name-rules.json') -Raw | ConvertFrom-Json -AsHashtable
foreach ($environment in @('ab', 'apictr-demo', ('a' * 32))) {
    foreach ($region in @('use', 'use2', 'insc')) {
        foreach ($subscription in @('s1', 's9999')) {
            $names = @{
                resourceGroup = Get-AzName 'rg' $region $subscription $environment
                apiCenter = Get-AzName 'apic' $region $subscription $environment
                apiManagement = Get-GlobalName 'apim' $region $subscription $environment 'abc123' '-' 50
                aiServices = Get-GlobalName 'ais' $region $subscription $environment 'abc' '-' 64
                aiProject = Get-AzName 'proj' $region $subscription $environment
                managedRedis = Get-GlobalName 'amr' $region $subscription $environment 'abc' '-' 60
            }
            foreach ($key in $names.Keys) {
                $rule = $rules.resources[$key]
                Assert-True ($names[$key].Length -le $rule.maxLength -and $names[$key] -cmatch $rule.charset) "Invalid $key name: $($names[$key])"
            }
            Assert-True ($names.apiManagement -match "^apim-$region-$subscription-.+-abc123$") 'Global name lost fixed segments.'
        }
    }
}
Assert-True ((Get-SubscriptionCode 'example-3') -eq 's3') 'Subscription code drifted.'
Assert-Throws { Get-SubscriptionCode 'example' } 'must end'
Assert-Throws { Assert-SubscriptionCode 'example-3' 's4' } 'does not match'
Assert-Throws { Get-LocationCode 'invalid' (Get-CoreCatalogPath 'location-codes.json') } 'no approved code'
Assert-True ((Get-LocationCode 'eastus' (Get-CoreCatalogPath 'location-codes.json')) -eq 'use') 'East US code drifted.'
$tags = Get-CommonTags 'owner/repo' 'demo' 'core' '2026-01-01T10:00:00-05:00' '2026-09-28T10:00:00-04:00'
Assert-True ($tags.Count -eq 7 -and -not $tags.Contains('owner')) 'Optional empty tags must be omitted.'

# Exercise loading and cleanup with fake CLIs; never touch Azure in this section.
& {
    $global:demoTestValues = @{
        AZURE_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000001'
        AZURE_ENV_NAME = 'unit-test'
        AZURE_LOCATION = 'eastus'
        AZURE_SUBSCRIPTION_CODE = 's1'
        DEPLOYMENT_PROFILE = 'core'
        AZURE_DEPLOYMENT_PROFILE = 'core'
        APIM_PUBLISHER_NAME = 'Example'
        APIM_PUBLISHER_EMAIL = 'team@example.com'
        AZURE_RESOURCE_GROUP = 'rg-use-s1-unit-test'
        AZURE_REPOSITORY = 'owner/repo'
        APIC_SERVICE = 'apic-from-output'
        APIC_PRINCIPAL_ID = '00000000-0000-0000-0000-000000000002'
        APIC_LOCATION = 'eastus'
        APIC_RESOURCE_ID = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-use-s1-unit-test/providers/Microsoft.ApiCenter/services/apic-from-output'
        APIM_SERVICE = 'apim-from-output'
        APIM_RESOURCE_ID = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-use-s1-unit-test/providers/Microsoft.ApiManagement/service/apim-from-output'
        APIM_GATEWAY_URL = 'https://actual-gateway.example'
    }
    $global:demoTestState = @{
        activeSubscription = $global:demoTestValues.AZURE_SUBSCRIPTION_ID
        groupTags = @{ 'azd-env-name' = 'unit-test'; repository = 'owner/repo'; 'managed-by' = 'azd' }
        confirmation = 'no'
        deleteCalled = $false
        deleteExitCode = 0
        azdExitCode = 0
        environments = @(
            @{ Name = 'unit-test'; IsDefault = $true }
            @{ Name = 'another-environment'; IsDefault = $false }
        )
        provisionCalled = $false
        previewExitCode = 0
        metadataCalls = @()
        metadataFailureName = ''
        demoCalls = @()
        demoFailureCall = 0
        principalId = '00000000-0000-0000-0000-000000000002'
        readerAssignment = 'reader-assignment'
        groupExists = 'false'
        apiCenters = @()
        resourceListExitCode = 0
        portalHostname = 'actual-portal.example'
        aiCatalogJson = '[]'
        spectralExitCode = 1
        spectralReport = '[{"code":"operation-operationId-required","path":["paths","/vehicles","get"],"message":"Missing operationId","severity":0}]'
    }
    function azd {
        $global:LASTEXITCODE = $global:demoTestState.azdExitCode
        if ($args[0] -eq 'env' -and $args[1] -eq 'list') {
            Assert-True ((Get-Location).Path -eq $root) 'Environment selection must run from the repository root.'
            ConvertTo-Json -InputObject $global:demoTestState.environments
            return
        }
        Assert-True ($args -notcontains '--environment') 'Scripts must not override normal azd environment precedence.'
        if ($args[0] -eq 'provision') {
            if ($args -contains '--preview') {
                $global:LASTEXITCODE = $global:demoTestState.previewExitCode
            }
            else { $global:demoTestState.provisionCalled = $true }
        }
        elseif ($args[0] -eq 'env' -and $args[1] -eq 'set') {
            $global:demoTestValues[$args[2]] = $args[3]
        }
        elseif ($args[0] -eq 'env' -and $args[1] -eq 'get-values') {
            if ($env:AZURE_ENV_NAME -eq 'missing-environment') {
                $global:LASTEXITCODE = 1
                return
            }
            $values = $global:demoTestValues.Clone()
            if (-not [string]::IsNullOrEmpty($env:AZURE_ENV_NAME)) {
                $values.AZURE_ENV_NAME = $env:AZURE_ENV_NAME
            }
            else {
                $values.AZURE_ENV_NAME = @($global:demoTestState.environments | Where-Object IsDefault)[0].Name
            }
            if ($values.AZURE_ENV_NAME -eq 'another-environment') {
                $values.AZURE_RESOURCE_GROUP = 'rg-use-s1-another-environment'
                $values.APIC_SERVICE = 'apic-another-environment'
                $values.APIC_RESOURCE_ID = "/subscriptions/$($values.AZURE_SUBSCRIPTION_ID)/resourceGroups/$($values.AZURE_RESOURCE_GROUP)/providers/Microsoft.ApiCenter/services/$($values.APIC_SERVICE)"
                $values.APIM_RESOURCE_ID = "/subscriptions/$($values.AZURE_SUBSCRIPTION_ID)/resourceGroups/$($values.AZURE_RESOURCE_GROUP)/providers/Microsoft.ApiManagement/service/apim-another-environment"
            }
            $values | ConvertTo-Json
        }
        else { throw "Unexpected azd invocation: $args" }
    }
    function az {
        $global:LASTEXITCODE = 0
        $command = "$($args[0]) $($args[1])"
        if ($command -in @('apic api', 'apic environment', 'apic show', 'apic integration', 'apim api', 'role assignment', 'resource show')) {
            $payloads = @{}
            $paths = @()
            foreach ($option in @('--custom-properties', '--specification', '--server')) {
                $index = [array]::IndexOf($args, $option)
                if ($index -ge 0) {
                    $argument = $args[$index + 1]
                    Assert-True ($argument.StartsWith('@')) "$option must use a JSON file."
                    $path = $argument.Substring(1)
                    $paths += $path
                    $payloads[$option] = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
                }
            }
            foreach ($option in @('--value', '--specification-path')) {
                $index = [array]::IndexOf($args, $option)
                if ($index -ge 0) {
                    $path = $args[$index + 1]
                    if ($option -eq '--value') {
                        Assert-True ($path.StartsWith('@')) 'Specification content must load from a file.'
                        $path = $path.Substring(1)
                    }
                    Assert-True ([System.IO.Path]::IsPathFullyQualified($path)) 'Sample path must not depend on the working directory.'
                    $payloads[$option] = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
                }
            }
            $global:demoTestState.demoCalls += @{ arguments = $args; payloads = $payloads; paths = $paths }
            if ($global:demoTestState.demoCalls.Count -eq $global:demoTestState.demoFailureCall) {
                $global:LASTEXITCODE = 42
                'ERROR: demo failure detail'
                return
            }
            if ($command -eq 'apic show' -and $args -contains 'identity.principalId') {
                $global:demoTestState.principalId
            }
            elseif ($command -eq 'role assignment') {
                $global:demoTestState.readerAssignment
            }
            elseif ($command -eq 'resource show') {
                $global:demoTestState.portalHostname
            }
            elseif ($command -eq 'apic api' -and $args -contains "[?title=='Utility AI demonstration'].{name:name,title:title}") {
                $global:demoTestState.aiCatalogJson
            }
            return
        }
        switch ("$($args[0]) $($args[1])") {
            'account show' {
                if ($args -contains 'id') { $global:demoTestState.activeSubscription }
                elseif ($args -contains 'name') { 'example-1' }
                else { @{ name = 'example-1'; state = 'Enabled' } | ConvertTo-Json }
            }
            'provider show' {
                @{
                    registrationState = 'Registered'
                    resourceTypes = @('services','service','workspaces','components') | ForEach-Object {
                        @{ resourceType = $_; locations = @('East US') }
                    }
                } | ConvertTo-Json -Depth 5
            }
            'apic integration' { }
            'apic metadata' {
                Assert-True ($args[2] -eq 'create') 'Unexpected metadata operation.'
                $name = $args[[array]::IndexOf($args, '--metadata-name') + 1]
                $schemaArgument = $args[[array]::IndexOf($args, '--schema') + 1]
                $assignmentsArgument = $args[[array]::IndexOf($args, '--assignments') + 1]
                Assert-True ($schemaArgument.StartsWith('@') -and $assignmentsArgument.StartsWith('@')) 'Metadata JSON must use file arguments for Windows az.cmd.'
                $schemaPath = $schemaArgument.Substring(1)
                $assignmentsPath = $assignmentsArgument.Substring(1)
                $global:demoTestState.metadataCalls += @{
                    name = $name
                    schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
                    assignments = Get-Content -LiteralPath $assignmentsPath -Raw | ConvertFrom-Json -NoEnumerate
                    paths = @($schemaPath, $assignmentsPath)
                }
                Assert-True ($args[[array]::IndexOf($args, '--resource-group') + 1] -eq $global:demoTestValues.AZURE_RESOURCE_GROUP) 'Metadata must use the deployed resource group.'
                Assert-True ($args[[array]::IndexOf($args, '--service-name') + 1] -eq $global:demoTestValues.APIC_SERVICE) 'Metadata must use the deployed service.'
                if ($name -eq $global:demoTestState.metadataFailureName) {
                    $global:LASTEXITCODE = 1
                    'ERROR: metadata failure detail'
                }
            }
            'group exists' { $global:demoTestState.groupExists }
            'resource list' {
                Assert-True ($args[[array]::IndexOf($args, '--resource-type') + 1] -eq 'Microsoft.ApiCenter/services' -and
                    $args[[array]::IndexOf($args, '--resource-group') + 1] -eq $global:demoTestValues.AZURE_RESOURCE_GROUP -and
                    $args[[array]::IndexOf($args, '--subscription') + 1] -eq $global:demoTestValues.AZURE_SUBSCRIPTION_ID) 'Plan discovery must be scoped to the selected API Center group and subscription.'
                $global:LASTEXITCODE = $global:demoTestState.resourceListExitCode
                ConvertTo-Json -InputObject $global:demoTestState.apiCenters -Depth 5
            }
            'group show' { @{ tags = $global:demoTestState.groupTags } | ConvertTo-Json }
            'group delete' {
                $global:demoTestState.deleteCalled = $true
                $global:LASTEXITCODE = $global:demoTestState.deleteExitCode
            }
            default { throw "Unexpected az invocation: $args" }
        }
    }
    function Read-Host { $global:demoTestState.confirmation }
    $saved = @{}
    foreach ($key in @($global:demoTestValues.Keys) + @('RESOURCE_GROUP','APIM_RESOURCE_GROUP','LOCATION','API_ID','API_TITLE','ENV_DEV','ENV_TEST','ENV_PROD')) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    }
    try {
        . (Join-Path $root 'scripts\deployment-context.ps1')
        Push-Location $PSScriptRoot
        try {
            $env:AZURE_ENV_NAME = $null
            $values = Get-DeploymentEnvironment -InformationVariable selectionLog
            Assert-True ($values.AZURE_ENV_NAME -eq 'unit-test') 'No process override must use the project default.'
            Assert-True (("$selectionLog" -match "'unit-test'") -and
                ("$selectionLog" -match 'source: project default')) 'Default selection must report its name and source.'
            $env:AZURE_ENV_NAME = 'another-environment'
            $values = Get-DeploymentEnvironment -InformationVariable selectionLog
            Assert-True ($values.AZURE_ENV_NAME -eq 'another-environment') 'Process override must take precedence over the project default.'
            Assert-True (("$selectionLog" -match "'another-environment'") -and
                ("$selectionLog" -match 'source: process AZURE_ENV_NAME')) 'Process selection must report its name and source.'
            Assert-True ($env:AZURE_ENV_NAME -eq 'another-environment') 'Reading the environment must not mutate process state.'
            Assert-True ((Get-Location).Path -eq $PSScriptRoot) 'Environment loading must restore the caller directory.'
            $env:AZURE_ENV_NAME = 'missing-environment'
            $failureLog = [System.Collections.Generic.List[string]]::new()
            Assert-Throws {
                Get-DeploymentEnvironment 6>&1 | ForEach-Object { $failureLog.Add([string]$_) }
            } 'Unable to load'
            Assert-True (("$failureLog" -match "'missing-environment'") -and
                ("$failureLog" -match 'source: process AZURE_ENV_NAME')) 'A failed load must report its selected name and source before throwing.'
            Assert-True ($env:AZURE_ENV_NAME -eq 'missing-environment') 'A stale override must not be silently cleared.'
            Assert-True ((Get-Location).Path -eq $PSScriptRoot) 'Failed environment loading must restore the caller directory.'
            $env:AZURE_ENV_NAME = $null
            $environments = $global:demoTestState.environments
            try {
                $global:demoTestState.environments = @()
                Show-DeploymentEnvironmentSelection -InformationVariable selectionLog
                Assert-True ("$selectionLog" -match '<not selected>') 'Missing selection must be reported without replacing azd selection behavior.'
            }
            finally {
                $global:demoTestState.environments = $environments
            }
        }
        finally {
            Pop-Location
        }
        . (Join-Path $root 'scripts\00-vars.ps1')
        Assert-True ($env:APIC_SERVICE -eq 'apic-from-output' -and $env:APIM_GATEWAY_URL -eq 'https://actual-gateway.example') 'Scripts must use outputs, not constructed names.'
        Assert-True ([string]::IsNullOrEmpty($env:AZURE_ENV_NAME) -and $deploymentEnvironmentName -eq 'unit-test') 'Loading outputs must not create a sticky process environment override.'
        try {
            $global:demoTestState.environments[0].IsDefault = $false
            $global:demoTestState.environments[1].IsDefault = $true
            . (Join-Path $root 'scripts\00-vars.ps1')
            Assert-True ($deploymentEnvironmentName -eq 'another-environment' -and
                $env:APIC_SERVICE -eq 'apic-another-environment' -and
                $env:RESOURCE_GROUP -eq 'rg-use-s1-another-environment' -and
                [string]::IsNullOrEmpty($env:AZURE_ENV_NAME)) 'Changing the azd default must load the new resource outputs in the same PowerShell session.'
            $env:AZURE_ENV_NAME = 'unit-test'
            . (Join-Path $root 'scripts\00-vars.ps1')
            Assert-True ($deploymentEnvironmentName -eq 'unit-test' -and $env:AZURE_ENV_NAME -eq 'unit-test' -and
                $env:APIC_SERVICE -eq 'apic-from-output') 'An intentional process override must be preserved and take precedence.'
            $env:AZURE_ENV_NAME = $null
            $global:demoTestState.groupTags.'azd-env-name' = 'another-environment'
            & (Join-Path $root 'scripts\99-cleanup.ps1')
            Assert-True (-not $global:demoTestState.deleteCalled -and
                $env:RESOURCE_GROUP -eq 'rg-use-s1-another-environment') 'Cleanup must verify the selected environment without a process override and still require confirmation.'
        }
        finally {
            $env:AZURE_ENV_NAME = $null
            $global:demoTestState.environments[0].IsDefault = $true
            $global:demoTestState.environments[1].IsDefault = $false
            $global:demoTestState.groupTags.'azd-env-name' = 'unit-test'
        }
        . (Join-Path $root 'scripts\00-vars.ps1')
        $global:demoTestState.activeSubscription = 'wrong'
        Assert-Throws { . (Join-Path $root 'scripts\00-vars.ps1') } 'subscriptions differ'
        $global:demoTestState.activeSubscription = $global:demoTestValues.AZURE_SUBSCRIPTION_ID
        $global:demoTestState.azdExitCode = 1
        Assert-Throws { . (Join-Path $root 'scripts\00-vars.ps1') } 'Unable to load'
        $global:demoTestState.azdExitCode = 0
        $gateway = $global:demoTestValues.APIM_GATEWAY_URL
        $global:demoTestValues.Remove('APIM_GATEWAY_URL')
        Assert-Throws { . (Join-Path $root 'scripts\00-vars.ps1') } 'Missing azd value'
        $global:demoTestValues.APIM_GATEWAY_URL = $gateway
        & (Join-Path $root 'scripts\02-metadata-schema.ps1')
        $calls = $global:demoTestState.metadataCalls
        Assert-True (($calls.name -join ',') -ceq 'lifecycleStage,businessOwner,complianceTag,department') 'Metadata names or creation order changed.'
        Assert-True ($calls[0].schema.type -eq 'string' -and
            ($calls[0].schema.oneOf.const -join ',') -eq 'design,development,testing,preview,production,deprecated,retired') 'Lifecycle schema changed.'
        Assert-True ($calls[1].schema.type -eq 'string') 'Business owner schema changed.'
        Assert-True ($calls[2].schema.type -eq 'array' -and $calls[2].schema.items.type -eq 'string' -and
            ($calls[2].schema.items.oneOf.const -join ',') -eq 'PCI,HIPAA,GDPR,SOC2,NERC-CIP,internal-only') 'Compliance multi-select schema changed.'
        Assert-True ($calls[3].schema.type -eq 'string') 'Department must be a string.'
        foreach ($call in $calls) {
            Assert-True ($call.assignments -is [array] -and $call.assignments.Count -eq 1) 'Assignments must remain a JSON array.'
            $assignment = $call.assignments[0]
            Assert-True ($assignment.entity -eq 'api' -and $assignment.deprecated -eq $false -and
                $assignment.required -eq ($call.name -in @('lifecycleStage', 'businessOwner'))) 'Metadata assignment changed.'
            foreach ($path in $call.paths) {
                Assert-True (-not (Test-Path -LiteralPath $path)) 'Metadata temporary file leaked after success.'
            }
        }
        foreach ($failureName in @('lifecycleStage', 'businessOwner', 'complianceTag', 'department')) {
            $global:demoTestState.metadataCalls = @()
            $global:demoTestState.metadataFailureName = $failureName
            Assert-Throws { & (Join-Path $root 'scripts\02-metadata-schema.ps1') } "Failed to create $failureName metadata \(Azure CLI exit code 1\):\s+ERROR: metadata failure detail"
            Assert-True ($global:demoTestState.metadataCalls[-1].name -eq $failureName) 'Metadata creation continued after failure.'
            foreach ($call in $global:demoTestState.metadataCalls) {
                foreach ($path in $call.paths) {
                    Assert-True (-not (Test-Path -LiteralPath $path)) 'Metadata temporary file leaked after failure.'
                }
            }
        }
        $global:demoTestState.metadataFailureName = ''
        . (Join-Path $PSScriptRoot 'demo-scripts.tests.ps1')
        & (Join-Path $root 'scripts\set-deployment-tags.ps1')
        $created = $global:demoTestValues.AZURE_CREATED_ON
        Assert-True ($created -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-0[45]:00$') 'Creation timestamp must have an Eastern offset.'
        & (Join-Path $root 'scripts\set-deployment-tags.ps1')
        Assert-True ($global:demoTestValues.AZURE_CREATED_ON -eq $created) 'Creation timestamp changed on rerun.'
        $global:demoTestValues.AZURE_CREATED_ON = '2026-07-01T12:00:00-05:00'
        Assert-Throws { & (Join-Path $root 'scripts\set-deployment-tags.ps1') } 'Eastern offset'
        $global:demoTestValues.AZURE_CREATED_ON = $created
        & (Join-Path $root 'scripts\preflight.ps1')
        Assert-True ((Get-DeploymentParameterValue @{} 'apiCenterSku') -eq $template.parameters.apiCenterSku.defaultValue) 'API Center script and Bicep defaults must agree.'
        $global:demoTestValues.API_CENTER_SKU = 'invalid'
        Assert-Throws { & (Join-Path $root 'scripts\preflight.ps1') } 'API_CENTER_SKU must be Free or Standard'
        $global:demoTestValues.API_CENTER_SKU = 'Free'
        $global:demoTestState.groupExists = 'true'
        & (Join-Path $root 'scripts\preflight.ps1')
        $global:demoTestState.apiCenters = @(
            @{ name = 'apic-use-s1-unit-test'; sku = @{ name = 'Free' } },
            @{ name = 'another-api-center'; sku = @{ name = 'Standard' } }
        )
        & (Join-Path $root 'scripts\preflight.ps1')
        $global:demoTestState.apiCenters[0].sku.name = 'Standard'
        Assert-Throws { & (Join-Path $root 'scripts\01-create-service.ps1') -PreviewOnly } 'refusing to downgrade.*azd env set API_CENTER_SKU Standard'
        Assert-True (-not $global:demoTestState.provisionCalled) 'Plan mismatch must stop provisioning.'
        $global:demoTestValues.API_CENTER_SKU = 'Standard'
        & (Join-Path $root 'scripts\preflight.ps1')
        $global:demoTestState.apiCenters[0].sku.name = $null
        Assert-Throws { & (Join-Path $root 'scripts\preflight.ps1') } 'Unable to determine the current plan'
        $global:demoTestState.resourceListExitCode = 1
        Assert-Throws { & (Join-Path $root 'scripts\preflight.ps1') } 'Azure check failed: az resource list'
        $global:demoTestState.resourceListExitCode = 0
        $global:demoTestState.groupExists = 'false'
        $global:demoTestValues.API_CENTER_SKU = 'Free'
        $global:demoTestValues.AZURE_LOCATION = 'eastus2'
        Assert-Throws { & (Join-Path $root 'scripts\preflight.ps1') } 'does not support'
        $global:demoTestValues.AZURE_LOCATION = 'eastus'
        $global:demoTestValues.DEPLOYMENT_PROFILE = 'private'
        Assert-Throws { & (Join-Path $root 'scripts\preflight.ps1') } 'only DEPLOYMENT_PROFILE=core'
        $global:demoTestValues.DEPLOYMENT_PROFILE = 'core'
        & (Join-Path $root 'scripts\01-create-service.ps1') -PreviewOnly
        Assert-True (-not $global:demoTestState.provisionCalled) 'PreviewOnly must never provision.'
        & (Join-Path $root 'scripts\01-create-service.ps1')
        Assert-True (-not $global:demoTestState.provisionCalled) 'Declined preview must never provision.'
        $global:demoTestState.previewExitCode = 1
        Assert-Throws { & (Join-Path $root 'scripts\01-create-service.ps1') } 'preview failed'
        Assert-True (-not $global:demoTestState.provisionCalled) 'Failed preview must never provision.'
        & (Join-Path $root 'scripts\99-cleanup.ps1')
        Assert-True (-not $global:demoTestState.deleteCalled) 'Declined cleanup must not delete.'
        $global:demoTestState.groupTags.repository = 'another/repo'
        Assert-Throws { & (Join-Path $root 'scripts\99-cleanup.ps1') } 'ownership tags'
        Assert-True (-not $global:demoTestState.deleteCalled) 'Unowned group must not be deleted.'
        $global:demoTestState.groupTags.repository = 'owner/repo'
        $global:demoTestState.confirmation = $global:demoTestValues.AZURE_RESOURCE_GROUP
        $global:demoTestState.deleteExitCode = 1
        Assert-Throws { & (Join-Path $root 'scripts\99-cleanup.ps1') } 'rejected'
    }
    finally {
        foreach ($key in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process')
        }
        Remove-Variable demoTestValues, demoTestState -Scope Global
    }
}
. (Join-Path $PSScriptRoot 'ai-platform.tests.ps1')
Write-Host 'All infrastructure, naming, syntax, and script safety checks passed.'
