# Load provisioned outputs, never reconstruct service names from user initials.
# $ErrorActionPreference = 'Stop'
# . (Join-Path $PSScriptRoot 'deployment-context.ps1')

# $deploymentValues = Get-DeploymentEnvironment
# $subscriptionId = Get-DeploymentValue $deploymentValues 'AZURE_SUBSCRIPTION_ID'
# Assert-DeploymentSubscription $subscriptionId
# $deploymentEnvironmentName = Get-DeploymentValue $deploymentValues 'AZURE_ENV_NAME'
# foreach ($key in @('AZURE_RESOURCE_GROUP', 'APIC_SERVICE',
#     'APIC_RESOURCE_ID', 'APIC_PRINCIPAL_ID', 'APIC_LOCATION',
#     'APIM_SERVICE', 'APIM_RESOURCE_ID', 'APIM_GATEWAY_URL',
#     'GRID_API_APP_URL', 'GRID_API_APP_NAME',
#     'GRID_MCP_APP_URL', 'GRID_MCP_APP_NAME')) {
#     $value = Get-DeploymentValue $deploymentValues $key
#     [Environment]::SetEnvironmentVariable($key, $value, 'Process')
# }

$env:NAMING_BASE = "s3-usc-apicdemo-initial-02"
$env:LOCATION = "centralus"
$env:AZURE_SUBSCRIPTION_ID = '4c88693f-5cc9-4f30-9d1e-d58d4221cf25' # $subscriptionId

$env:RESOURCE_GROUP = "rg-$env:NAMING_BASE"
$env:APIM_RESOURCE_GROUP = $env:RESOURCE_GROUP  # "<existing-test-apim-resource-group>"

$env:APIM_SERVICE = "apim-$env:NAMING_BASE"
$env:APIC_SERVICE = "apic-$env:NAMING_BASE"


# $env:RESOURCE_GROUP = $env:AZURE_RESOURCE_GROUP
# $env:APIM_RESOURCE_GROUP = $env:AZURE_RESOURCE_GROUP
# $env:LOCATION = $env:APIC_LOCATION
$env:API_ID = 'fleet-vehicle-api'
$env:API_TITLE = 'Fleet Vehicle API'
$env:ENV_DEV = 'dev'
$env:ENV_TEST = 'test'
$env:ENV_PROD = 'prod'

az account set --subscription $env:AZURE_SUBSCRIPTION_ID
if ($LASTEXITCODE -ne 0) { throw "Failed to select subscription '$($env:AZURE_SUBSCRIPTION_ID)'. Run 'az login' first." }

Write-Host "Subscription: $env:AZURE_SUBSCRIPTION_ID; resource group: $env:RESOURCE_GROUP ($env:LOCATION)"
Write-Host "API Center: $env:APIC_SERVICE; APIM: $env:APIM_SERVICE ($env:APIM_RESOURCE_GROUP)"
