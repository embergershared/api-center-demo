# Identity and RBAC are owned by Bicep; this step owns only the demo integration.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-vars.ps1')
. (Join-Path $PSScriptRoot 'demo-cli.ps1')

$null = Invoke-DemoAz -Arguments @('apic', 'integration', 'create', 'apim', '--help') `
    -FailureMessage 'Install apic-extension 1.2.0b1 or newer with preview support'

Write-Host '==> Checking the provisioned API Center identity and APIM reader assignment'
$principalId = Invoke-DemoAz -Arguments @(
    'apic', 'show', '--resource-group', $env:RESOURCE_GROUP, '--name', $env:APIC_SERVICE,
    '--query', 'identity.principalId', '--output', 'tsv'
) -FailureMessage 'Failed to retrieve the API Center identity'
if ($principalId -ne $env:APIC_PRINCIPAL_ID) {
    throw 'API Center identity does not match the deployment. Run azd provision, then azd env refresh.'
}
$assignment = Invoke-DemoAz -Arguments @(
    'role', 'assignment', 'list', '--scope', $env:APIM_RESOURCE_ID,
    '--query', "[?principalId=='$principalId' && roleDefinitionName=='API Management Service Reader Role'].id | [0]",
    '--output', 'tsv'
) -FailureMessage 'Failed to retrieve the APIM Reader assignment'
if ([string]::IsNullOrWhiteSpace($assignment)) {
    throw 'API Center is missing its provisioned APIM Reader assignment. Run azd provision.'
}

Write-Host "==> Integrating API Management with API Center ($env:APIM_SERVICE)"
Invoke-DemoAz -Arguments @(
    'apic', 'integration', 'create', 'apim',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--integration-name', 'apim-integration',
    '--azure-apim', $env:APIM_RESOURCE_ID,
    '--output', 'table'
) -FailureMessage 'Failed to integrate API Management with API Center'
Write-Host '==> Synchronization configured; API inventory updates are asynchronous.'
Write-Host '    In API Center, inspect apim-integration and confirm the imported APIs came from this APIM instance.'
Write-Host '    For the full profile, run script 08 to check for the Utility AI demonstration catalog entry.'
Write-Host '==> API Center defaults to Standard. Verify the plan in Overview > Manage plan.'
Write-Host '    If this environment explicitly uses Free, upgrade in the portal after linking, then run: azd env set API_CENTER_SKU Standard'
Write-Host '    Integration creation alone does not confirm synchronization completion or a plan upgrade.'
