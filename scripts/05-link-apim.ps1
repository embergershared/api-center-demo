# Identity and RBAC are owned by Bicep; link only after verifying those prerequisites.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deployment-context.ps1')
. (Join-Path $PSScriptRoot 'demo-cli.ps1')

function Set-ApimIntegration {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary] $Values,
        [ValidateRange(1, 121)][int] $StateChecks = 31
    )

    $subscription = Get-DeploymentValue $Values 'AZURE_SUBSCRIPTION_ID'
    Assert-DeploymentSubscription $subscription
    $resourceGroup = Get-DeploymentValue $Values 'AZURE_RESOURCE_GROUP'
    $serviceName = Get-DeploymentValue $Values 'APIC_SERVICE'
    $serviceId = Get-DeploymentValue $Values 'APIC_RESOURCE_ID'
    $expectedPrincipalId = Get-DeploymentValue $Values 'APIC_PRINCIPAL_ID'
    $apimId = Get-DeploymentValue $Values 'APIM_RESOURCE_ID'
    $expectedSku = Get-DeploymentParameterValue $Values 'apiCenterSku'
    $scope = @('--subscription', $subscription, '--resource-group', $resourceGroup, '--service-name', $serviceName)
    $integrationName = 'apim-integration'

    $null = Invoke-DemoAz -Arguments @('apic', 'integration', 'create', 'apim', '--help') `
        -FailureMessage 'Install apic-extension 1.2.0b1 or newer with preview support'
    Write-Host '==> Checking the provisioned API Center identity, plan, and APIM reader assignment'
    $service = (Invoke-DemoAz -Arguments @(
        'apic', 'show', '--subscription', $subscription, '--resource-group', $resourceGroup,
        '--name', $serviceName, '--output', 'json'
    ) -FailureMessage 'Failed to retrieve API Center') -join [Environment]::NewLine | ConvertFrom-Json
    if ($service.id -ine $serviceId -or [string]::IsNullOrWhiteSpace($service.identity.principalId) -or
        $service.identity.principalId -ine $expectedPrincipalId) {
        throw 'API Center identity does not match the deployment. Run azd provision, then azd env refresh.'
    }
    if ($service.sku.name -cne $expectedSku) {
        throw "API Center plan '$($service.sku.name)' does not match '$expectedSku'. Align API_CENTER_SKU and run azd provision before linking."
    }
    if ($expectedSku -eq 'Free') {
        Write-Warning 'This environment explicitly uses Free. To use Standard features, upgrade the plan and run: azd env set API_CENTER_SKU Standard'
    }
    $principalId = $service.identity.principalId
    $tenantId = $service.identity.tenantId
    $systemIdentityReference = "$tenantId/$principalId/systemAssigned"
    $readerRoleId = "/subscriptions/$subscription/providers/Microsoft.Authorization/roleDefinitions/71522526-b88f-4d52-b57f-d31fc3546d0d"
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $assignment = Invoke-DemoAz -Arguments @(
            'role', 'assignment', 'list', '--subscription', $subscription, '--scope', $apimId,
            '--query', "[?principalId=='$principalId' && roleDefinitionId=='$readerRoleId'].id | [0]",
            '--output', 'tsv'
        ) -FailureMessage 'Failed to retrieve the APIM Reader assignment'
        if (-not [string]::IsNullOrWhiteSpace($assignment)) { break }
        if ($attempt -eq 6) {
            throw "API Center identity '$principalId' is missing its provisioned APIM Reader assignment on '$apimId'. Run azd provision."
        }
        Write-Warning "APIM Reader assignment is not visible yet (attempt $attempt/6); retrying in 20 seconds."
        Start-Sleep -Seconds 20
    }

    function Get-ExistingApimIntegration {
        $json = (Invoke-DemoAz -Arguments (@('apic', 'integration', 'list') + $scope + @('--output', 'json')) `
            -FailureMessage 'Failed to list API Center integrations') -join [Environment]::NewLine
        $integrations = ConvertFrom-Json -InputObject $json -NoEnumerate
        if ($integrations -isnot [array]) { throw 'API Center integration list did not return an array.' }
        $matches = @($integrations | Where-Object { $_.azureApiManagementSource.resourceId -ieq $apimId })
        if ($matches.Count -gt 1) {
            throw "Multiple integrations target '$apimId'. Resolve the duplicate links in API Center; no links were changed."
        }
        if ($matches.Count -eq 1) { return $matches[0] }
        if (@($integrations | Where-Object name -EQ $integrationName).Count) {
            throw "Integration '$integrationName' already targets another source; no links were changed."
        }
    }

    # Retry permission propagation as in initial-snapshot; discover before each PUT to avoid resetting an accepted link.
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $existing = Get-ExistingApimIntegration
        if ($existing) {
            $integrationName = $existing.name
            Write-Host "==> Reusing APIM integration '$integrationName' without changing it"
            break
        }
        try {
            $null = Invoke-DemoAz -Arguments (@('apic', 'integration', 'create', 'apim') + $scope + @(
                '--integration-name', $integrationName, '--azure-apim', $apimId, '--output', 'json'
            )) -FailureMessage 'Failed to integrate API Management with API Center'
            break
        }
        catch {
            $transient = $_.Exception.Message -match 'AuthorizationFailed|Forbidden|does not have authorization|permission|TooManyRequests|429|ServiceUnavailable|InternalServerError|GatewayTimeout|temporar|timed out'
            if (-not $transient -or $attempt -eq 6) { throw }
            Write-Warning "Integration creation failed (attempt $attempt/6): $($_.Exception.Message). Retrying in 20 seconds."
            Start-Sleep -Seconds 20
        }
    }

    $diagnosticCommand = "az apic integration show --subscription $subscription --resource-group $resourceGroup --service-name $serviceName --integration-name $integrationName --output json"
    for ($check = 1; $check -le $StateChecks; $check++) {
        $link = (Invoke-DemoAz -Arguments (@('apic', 'integration', 'show') + $scope + @(
            '--integration-name', $integrationName, '--output', 'json'
        )) -FailureMessage 'Failed to read APIM integration state') -join [Environment]::NewLine | ConvertFrom-Json
        $identityReference = $link.azureApiManagementSource.msiResourceId
        # Azure may resolve an omitted MSI field into the API Center tenant/principal reference.
        $usesSystemIdentity = [string]::IsNullOrWhiteSpace($identityReference) -or (
            -not [string]::IsNullOrWhiteSpace($tenantId) -and
            $identityReference -ieq $systemIdentityReference
        )
        if ($link.azureApiManagementSource.resourceId -ine $apimId -or -not $usesSystemIdentity) {
            throw "Integration '$integrationName' does not use the expected APIM source and API Center system-assigned identity. Inspect it with: $diagnosticCommand"
        }
        $state = $link.linkState.state
        Write-Host "==> APIM integration '$integrationName': $state (last updated: $($link.linkState.lastUpdatedOn))"
        if ($state -eq 'syncing') {
            Write-Host 'API Center reports an active synchronization link. Individual API inventory updates remain asynchronous.'
            Write-Host 'Verify imported entries reference this integration; managed catalog entries alone do not prove synchronization.'
            return
        }
        if ($state -ne 'initializing') {
            throw "APIM integration '$integrationName' is not syncing: '$state'. $($link.linkState.message) Inspect it with: $diagnosticCommand"
        }
        if ($check -lt $StateChecks) { Start-Sleep -Seconds 20 }
    }
    throw "APIM integration '$integrationName' is still initializing after $StateChecks state checks. $($link.linkState.message) The link was left intact; rerun script 05 to check it again. Inspect it with: $diagnosticCommand"
}

if ($MyInvocation.InvocationName -ne '.') {
    Set-ApimIntegration -Values (Get-DeploymentEnvironment)
}
