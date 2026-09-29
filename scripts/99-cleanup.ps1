# Delete only the selected, verified demo environment.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-vars.ps1')

$groupJson = az group show --name $env:RESOURCE_GROUP --subscription $env:AZURE_SUBSCRIPTION_ID --output json
if ($LASTEXITCODE -ne 0) { throw 'Unable to verify the resource group; cleanup aborted.' }
$group = $groupJson | ConvertFrom-Json
$repository = Get-DeploymentValue $deploymentValues 'AZURE_REPOSITORY'
if ($group.tags.'azd-env-name' -ne $deploymentEnvironmentName -or
    $group.tags.repository -ne $repository -or $group.tags.'managed-by' -ne 'azd') {
    throw 'Resource-group ownership tags do not match this deployment; cleanup aborted.'
}
$expectedPrefix = "/subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/$env:RESOURCE_GROUP/providers/"
if (-not $env:APIC_RESOURCE_ID.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not $env:APIM_RESOURCE_ID.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Deployment resource IDs do not belong to the selected group; cleanup aborted.'
}
Write-Host "Subscription: $env:AZURE_SUBSCRIPTION_ID; environment: $deploymentEnvironmentName"
$confirmation = Read-Host "Type '$env:RESOURCE_GROUP' to delete this group and ALL its resources"
if ($confirmation -cne $env:RESOURCE_GROUP) {
    Write-Host 'Aborted.'
    return
}
az group delete --name $env:RESOURCE_GROUP --subscription $env:AZURE_SUBSCRIPTION_ID --yes --no-wait
if ($LASTEXITCODE -ne 0) { throw 'Azure rejected the resource-group deletion request.' }
Write-Host "Deletion requested for $env:RESOURCE_GROUP. Completion is asynchronous."
