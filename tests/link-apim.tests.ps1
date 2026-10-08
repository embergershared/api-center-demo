$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\05-link-apim.ps1')

function Assert-Link([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-LinkFailure([string] $Pattern) {
    try { $null = Set-ApimIntegration -Values $values -StateChecks 3 6>&1 3>&1 }
    catch {
        Assert-Link ($_.Exception.Message -match $Pattern) "Unexpected failure: $_"
        return
    }
    throw "Expected failure matching '$Pattern'."
}
function Get-LinkArgument($Arguments, [string] $Name) {
    $index = [array]::IndexOf($Arguments, $Name)
    Assert-Link ($index -ge 0) "Missing option $Name."
    $Arguments[$index + 1]
}
$values = @{
    AZURE_SUBSCRIPTION_ID = '00000000-0000-0000-0000-000000000001'
    AZURE_RESOURCE_GROUP = 'test-group'
    APIC_SERVICE = 'test-center'
    APIC_RESOURCE_ID = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-group/providers/Microsoft.ApiCenter/services/test-center'
    APIC_PRINCIPAL_ID = '00000000-0000-0000-0000-000000000002'
    APIM_RESOURCE_ID = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-group/providers/Microsoft.ApiManagement/service/test-gateway'
}
$tenantId = '00000000-0000-0000-0000-000000000003'
function New-TestLink([string] $Name = 'apim-integration') {
    @{
        name = $Name
        azureApiManagementSource = @{
            resourceId = $values.APIM_RESOURCE_ID
            msiResourceId = "$tenantId/$($values.APIC_PRINCIPAL_ID)/systemAssigned"
        }
        linkState = @{ state = 'syncing'; message = 'service detail'; lastUpdatedOn = '2026-10-06T12:00:00Z' }
    }
}
function Reset-LinkTest {
    $script:linkTestState = @{
        subscription = $values.AZURE_SUBSCRIPTION_ID
        service = @{
            id = $values.APIC_RESOURCE_ID
            identity = @{ principalId = $values.APIC_PRINCIPAL_ID; tenantId = $tenantId; type = 'SystemAssigned' }
            sku = @{ name = 'Standard' }
        }
        integrations = @()
        link = (New-TestLink)
        states = @('syncing')
        calls = [System.Collections.Generic.List[object]]::new()
        sleeps = 0
        roleReads = 0
        missingRoleReads = 0
        createCalls = 0
        createFailures = 0
        createError = 'AuthorizationFailed: role permission has not propagated'
        acceptedOnFailure = $false
        showCalls = 0
        failCommand = ''
        malformedList = $false
    }
    $values.Remove('API_CENTER_SKU')
}
function Start-Sleep {
    param([int] $Seconds)
    Assert-Link ($Seconds -eq 20) 'Snapshot retry interval changed.'
    $script:linkTestState.sleeps++
}
function az {
    $global:LASTEXITCODE = 0
    $state = $script:linkTestState
    if (($args[0..1] -join ' ') -eq 'account show') { return $state.subscription }
    $command = if ($args -contains '--help') { 'help' } else { $args[0..2] -join ' ' }
    $state.calls.Add(@{ command = $command; arguments = @($args) })
    if ($command -eq $state.failCommand) {
        $global:LASTEXITCODE = 42
        return 'ERROR: fixture CLI failure'
    }
    if ($command -eq 'help') { return }
    Assert-Link ((Get-LinkArgument $args '--subscription') -eq $values.AZURE_SUBSCRIPTION_ID) 'Every request must select the deployment subscription.'
    if ($command -eq 'role assignment list') {
        Assert-Link ((Get-LinkArgument $args '--scope') -eq $values.APIM_RESOURCE_ID) 'Role lookup must be scoped to the provisioned APIM.'
        $query = Get-LinkArgument $args '--query'
        Assert-Link ($query -match [regex]::Escape($values.APIC_PRINCIPAL_ID) -and
            $query -match '71522526-b88f-4d52-b57f-d31fc3546d0d' -and
            $query -notmatch 'roleDefinitionName') 'Role lookup must bind the API Center principal and stable Reader role ID.'
        $state.roleReads++
        if ($state.roleReads -gt $state.missingRoleReads) { return 'reader-assignment' }
        return
    }
    Assert-Link ((Get-LinkArgument $args '--resource-group') -eq $values.AZURE_RESOURCE_GROUP) 'Wrong API Center resource group.'
    if (($args[0..1] -join ' ') -eq 'apic show') {
        Assert-Link ((Get-LinkArgument $args '--name') -eq $values.APIC_SERVICE) 'Wrong API Center name.'
        return $state.service | ConvertTo-Json -Depth 10
    }
    Assert-Link ((Get-LinkArgument $args '--service-name') -eq $values.APIC_SERVICE) 'Wrong integration service.'
    switch ($command) {
        'apic integration list' {
            if ($state.malformedList) { return '{}' }
            return ConvertTo-Json -InputObject $state.integrations -Depth 10
        }
        'apic integration create' {
            Assert-Link ($args[3] -eq 'apim' -and
                (Get-LinkArgument $args '--azure-apim') -eq $values.APIM_RESOURCE_ID) 'Must use the supported APIM integration command and exact source.'
            Assert-Link ($args -notcontains '--target-environment-id' -and $args -notcontains '--msi-resource-id') 'Let Azure create its sync environment and use API Center system identity, as in the snapshot.'
            $state.createCalls++
            if ($state.createCalls -le $state.createFailures) {
                if ($state.acceptedOnFailure) { $state.integrations = @($state.link) }
                $global:LASTEXITCODE = 42
                return "ERROR: $($state.createError)"
            }
            $state.integrations = @($state.link)
            return $state.link | ConvertTo-Json -Depth 10
        }
        'apic integration show' {
            Assert-Link ((Get-LinkArgument $args '--integration-name') -eq $state.link.name) 'Must reuse the existing integration name.'
            $index = [Math]::Min($state.showCalls, $state.states.Count - 1)
            $state.link.linkState.state = $state.states[$index]
            $state.showCalls++
            return $state.link | ConvertTo-Json -Depth 10
        }
        default { throw "Unexpected Azure command: $args" }
    }
}

Reset-LinkTest
$script:linkTestState.states = @('initializing', 'syncing')
$log = Set-ApimIntegration -Values $values -StateChecks 3 6>&1 3>&1
Assert-Link ($script:linkTestState.createCalls -eq 1 -and $script:linkTestState.sleeps -eq 1) 'New links must wait for syncing.'
Assert-Link ("$log" -match 'Individual API inventory updates remain asynchronous') 'An active link must not imply complete inventory synchronization.'
$null = Set-ApimIntegration -Values $values -StateChecks 3 6>&1 3>&1
Assert-Link ($script:linkTestState.createCalls -eq 1) 'Reruns must not recreate an existing link.'

Reset-LinkTest
$script:linkTestState.link = New-TestLink 'sync-from-test-gateway'
$script:linkTestState.integrations = @($script:linkTestState.link)
$null = Set-ApimIntegration -Values $values 6>&1 3>&1
Assert-Link ($script:linkTestState.createCalls -eq 0) 'Snapshot-named links must be reused.'

foreach ($identityShape in @('omitted', 'null', 'empty', 'whitespace', 'uppercase')) {
    Reset-LinkTest
    $source = $script:linkTestState.link.azureApiManagementSource
    switch ($identityShape) {
        omitted { $source.Remove('msiResourceId') }
        null { $source.msiResourceId = $null }
        empty { $source.msiResourceId = '' }
        whitespace { $source.msiResourceId = ' ' }
        uppercase { $source.msiResourceId = $source.msiResourceId.ToUpperInvariant() }
    }
    $script:linkTestState.integrations = @($script:linkTestState.link)
    $null = Set-ApimIntegration -Values $values -StateChecks 3 6>&1 3>&1
    Assert-Link ($script:linkTestState.createCalls -eq 0 -and
        $script:linkTestState.showCalls -eq 1) "Valid system-assigned identity form '$identityShape' must be reused without changing the link."
}

foreach ($property in @('principalId', 'serviceId', 'plan')) {
    Reset-LinkTest
    switch ($property) {
        principalId { $script:linkTestState.service.identity.principalId = ''; $pattern = 'identity does not match' }
        serviceId { $script:linkTestState.service.id = 'wrong'; $pattern = 'identity does not match' }
        plan { $script:linkTestState.service.sku.name = 'Free'; $pattern = 'plan.*does not match' }
    }
    Assert-LinkFailure $pattern
    Assert-Link ($script:linkTestState.roleReads -eq 0 -and $script:linkTestState.createCalls -eq 0) 'Invalid deployment identity or plan must block linking.'
}
Reset-LinkTest
$script:linkTestState.subscription = 'wrong-subscription'
Assert-LinkFailure 'subscriptions differ'
Assert-Link ($script:linkTestState.calls.Count -eq 0) 'Subscription mismatch must block Azure operations.'

Reset-LinkTest
$values.API_CENTER_SKU = 'Free'
$script:linkTestState.service.sku.name = 'Free'
$log = Set-ApimIntegration -Values $values 6>&1 3>&1
Assert-Link ("$log" -match 'azd env set API_CENTER_SKU Standard') 'Explicit Free must warn without silently upgrading.'

Reset-LinkTest
$script:linkTestState.missingRoleReads = 2
$script:linkTestState.createFailures = 2
$null = Set-ApimIntegration -Values $values 6>&1 3>&1
Assert-Link ($script:linkTestState.roleReads -eq 3 -and $script:linkTestState.createCalls -eq 3 -and
    $script:linkTestState.sleeps -eq 4) 'Retry both role visibility and permission propagation.'

Reset-LinkTest
$script:linkTestState.missingRoleReads = 6
Assert-LinkFailure 'missing its provisioned APIM Reader assignment'
Assert-Link ($script:linkTestState.roleReads -eq 6 -and $script:linkTestState.createCalls -eq 0 -and
    $script:linkTestState.sleeps -eq 5) 'Missing Reader must stop after six checks, before creating a link.'

Reset-LinkTest
$script:linkTestState.createFailures = 6
Assert-LinkFailure 'AuthorizationFailed'
Assert-Link ($script:linkTestState.createCalls -eq 6 -and $script:linkTestState.showCalls -eq 0 -and
    $script:linkTestState.sleeps -eq 5) 'Creation retries must be bounded and preserve the final Azure error.'

Reset-LinkTest
$script:linkTestState.createFailures = 1
$script:linkTestState.acceptedOnFailure = $true
$null = Set-ApimIntegration -Values $values 6>&1 3>&1
Assert-Link ($script:linkTestState.createCalls -eq 1) 'An accepted request with a lost response must be discovered, not recreated.'

Reset-LinkTest
$script:linkTestState.createFailures = 1
$script:linkTestState.createError = 'BadRequest: invalid configuration'
Assert-LinkFailure 'BadRequest'
Assert-Link ($script:linkTestState.createCalls -eq 1 -and $script:linkTestState.sleeps -eq 0) 'Permanent configuration errors must not be retried.'

foreach ($linkState in @('initializing', 'failed', 'disabled', 'unknown', '')) {
    Reset-LinkTest
    $script:linkTestState.integrations = @($script:linkTestState.link)
    $script:linkTestState.states = @($linkState)
    Assert-LinkFailure 'service detail.*az apic integration show'
    Assert-Link ($script:linkTestState.createCalls -eq 0) 'Unhealthy links must not be overwritten or deleted.'
    if ($linkState -eq 'initializing') {
        Assert-Link ($script:linkTestState.showCalls -eq 3 -and $script:linkTestState.sleeps -eq 2) 'Stuck initialization must time out, not report success.'
    }
    else { Assert-Link ($script:linkTestState.showCalls -eq 1) 'Unexpected states must fail immediately.' }
}

foreach ($case in @('collision', 'duplicate', 'wrong-source', 'wrong-identity',
    'wrong-tenant', 'wrong-principal', 'missing-tenant', 'user-assigned', 'malformed')) {
    Reset-LinkTest
    switch ($case) {
        collision {
            $other = New-TestLink
            $other.azureApiManagementSource.resourceId = 'another-source'
            $script:linkTestState.integrations = @($other)
            $pattern = 'already targets another source'
        }
        duplicate {
            $script:linkTestState.integrations = @((New-TestLink), (New-TestLink 'duplicate'))
            $pattern = 'Multiple integrations'
        }
        wrong-source {
            $script:linkTestState.link.azureApiManagementSource.resourceId = 'another-source'
            $pattern = 'expected APIM source'
        }
        wrong-identity {
            $script:linkTestState.link.azureApiManagementSource.msiResourceId = 'user-assigned-identity'
            $pattern = 'system-assigned identity'
        }
        wrong-tenant {
            $script:linkTestState.link.azureApiManagementSource.msiResourceId = "another-tenant/$($values.APIC_PRINCIPAL_ID)/systemAssigned"
            $pattern = 'system-assigned identity'
        }
        wrong-principal {
            $script:linkTestState.link.azureApiManagementSource.msiResourceId = "$tenantId/another-principal/systemAssigned"
            $pattern = 'system-assigned identity'
        }
        missing-tenant {
            $script:linkTestState.service.identity.tenantId = ''
            $pattern = 'system-assigned identity'
        }
        user-assigned {
            $script:linkTestState.link.azureApiManagementSource.msiResourceId = "$tenantId/$($values.APIC_PRINCIPAL_ID)/userAssigned"
            $pattern = 'system-assigned identity'
        }
        malformed { $script:linkTestState.malformedList = $true; $pattern = 'did not return an array' }
    }
    Assert-LinkFailure $pattern
}

foreach ($command in @('help', 'apic show --subscription', 'role assignment list', 'apic integration list',
    'apic integration create', 'apic integration show')) {
    Reset-LinkTest
    $script:linkTestState.failCommand = $command
    Assert-LinkFailure '(?s)Azure CLI exit code 42.*fixture CLI failure'
    Assert-Link ($script:linkTestState.calls[-1].command -eq $command) 'CLI failure must stop subsequent commands.'
}
Write-Host 'APIM integration checks passed.'
