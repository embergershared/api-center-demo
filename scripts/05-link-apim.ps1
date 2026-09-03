# 05-link-apim.ps1 — integrate the demo APIM instance so its APIs
# sync automatically into API Center (built-in sync, not a one-time import).
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

$null = az extension add --name apic-extension --upgrade --allow-preview true --yes 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "Failed to install or upgrade the preview apic-extension required for APIM integration."
}

$null = az apic integration create apim --help 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "The installed apic-extension does not provide 'az apic integration create apim'. Version 1.2.0b1 or later is required."
}

Write-Host "==> Enabling the API Center system-assigned managed identity"
az apic update `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:APIC_SERVICE `
  --identity '{"type":"SystemAssigned"}' `
  -o none
if ($LASTEXITCODE -ne 0) { throw "Failed to enable the API Center managed identity." }

$ApicPrincipalId = az apic show `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:APIC_SERVICE `
  --query identity.principalId `
  -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ApicPrincipalId)) {
  throw "Failed to get the API Center managed identity principal ID."
}

$ApimId = az apim show `
  --resource-group $env:APIM_RESOURCE_GROUP `
  --name $env:APIM_SERVICE `
  --query id -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ApimId)) {
  throw "Failed to get API Management service '$($env:APIM_SERVICE)'."
}

Write-Host "==> Granting API Center read-only access to API Management"
$ExistingRoleAssignmentId = az role assignment list `
  --assignee-object-id $ApicPrincipalId `
  --role "API Management Service Reader Role" `
  --scope $ApimId `
  --query "[?scope=='$ApimId'].id | [0]" `
  -o tsv
if ($LASTEXITCODE -ne 0) { throw "Failed to check API Center read access to API Management." }

if ([string]::IsNullOrWhiteSpace($ExistingRoleAssignmentId)) {
  az role assignment create `
    --assignee-object-id $ApicPrincipalId `
    --assignee-principal-type ServicePrincipal `
    --role "API Management Service Reader Role" `
    --scope $ApimId `
    -o none
  if ($LASTEXITCODE -ne 0) { throw "Failed to grant API Center read access to API Management." }
} else {
  Write-Host "    Reader role assignment already exists."
}

Write-Host "==> Integrating API Management with API Center ($($env:APIM_SERVICE))"
az apic integration create apim `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --integration-name "apim-integration" `
  --azure-apim $ApimId `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to integrate API Management with API Center." }

Write-Host "==> All APIs currently in $($env:APIM_SERVICE) will now show up in the API Center catalog,"
Write-Host "    and stay in sync automatically as APIs are added/changed/removed in APIM."
