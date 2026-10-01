# Load provisioned outputs, never reconstruct service names from user initials.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deployment-context.ps1')

$deploymentValues = Get-DeploymentEnvironment
$subscriptionId = Get-DeploymentValue $deploymentValues 'AZURE_SUBSCRIPTION_ID'
Assert-DeploymentSubscription $subscriptionId
$deploymentEnvironmentName = Get-DeploymentValue $deploymentValues 'AZURE_ENV_NAME'
foreach ($key in @('AZURE_RESOURCE_GROUP', 'APIC_SERVICE',
    'APIC_RESOURCE_ID', 'APIC_PRINCIPAL_ID', 'APIC_LOCATION',
    'APIM_SERVICE', 'APIM_RESOURCE_ID', 'APIM_GATEWAY_URL',
    'GRID_API_APP_URL', 'GRID_API_APP_NAME',
    'GRID_MCP_APP_URL', 'GRID_MCP_APP_NAME')) {
    $value = Get-DeploymentValue $deploymentValues $key
    [Environment]::SetEnvironmentVariable($key, $value, 'Process')
}
$env:AZURE_SUBSCRIPTION_ID = $subscriptionId
$env:RESOURCE_GROUP = $env:AZURE_RESOURCE_GROUP
$env:APIM_RESOURCE_GROUP = $env:AZURE_RESOURCE_GROUP
$env:LOCATION = $env:APIC_LOCATION
$env:API_ID = 'fleet-vehicle-api'
$env:API_TITLE = 'Fleet Vehicle API'
$env:ENV_DEV = 'dev'
$env:ENV_TEST = 'test'
$env:ENV_PROD = 'prod'

Write-Host "Environment: $deploymentEnvironmentName; resource group: $env:RESOURCE_GROUP"
Write-Host "API Center: $env:APIC_SERVICE ($env:APIC_LOCATION); APIM: $env:APIM_SERVICE"
