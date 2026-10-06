# 05-link-apim.ps1 — OPTIONAL: link an existing APIM instance so its APIs
# sync automatically into API Center (built-in sync, not a one-time import).
# Requires APIM_SERVICE to be set in 00-vars.ps1.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

if ([string]::IsNullOrEmpty($env:APIM_SERVICE)) {
    Write-Host "APIM_SERVICE is not set in 00-vars.ps1 — skipping. This step needs an existing APIM instance."
    exit 0
}

Write-Host "==> Ensuring apic-extension with 'az apic integration' (preview) is installed"
az extension add --name apic-extension --upgrade --allow-preview true --yes
if ($LASTEXITCODE -ne 0) { throw "Failed to install or upgrade apic-extension." }

Write-Host "==> Fetching the APIM resource ID"
$ApimId = az apim show `
  --resource-group $env:APIM_RESOURCE_GROUP `
  --name $env:APIM_SERVICE `
  --query id -o tsv
if ($LASTEXITCODE -ne 0 -or -not $ApimId) { throw "Failed to find APIM '$($env:APIM_SERVICE)'." }

Write-Host "==> Enabling system-assigned managed identity on API Center"
$PrincipalId = az apic update `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:APIC_SERVICE `
  --identity '{type:SystemAssigned}' `
  --query identity.principalId -o tsv
if ($LASTEXITCODE -ne 0 -or -not $PrincipalId) { throw "Failed to enable managed identity on '$($env:APIC_SERVICE)'." }

Write-Host "==> Granting 'API Management Service Reader Role' on APIM to the API Center identity"
$RoleName = "API Management Service Reader Role"
$Existing = az role assignment list --assignee $PrincipalId --role $RoleName --scope $ApimId --query "[0].id" -o tsv
if (-not $Existing) {
  az role assignment create `
    --assignee-object-id $PrincipalId `
    --assignee-principal-type ServicePrincipal `
    --role $RoleName `
    --scope $ApimId `
    -o none
  if ($LASTEXITCODE -ne 0) { throw "Failed to assign '$RoleName' on APIM." }
}

Write-Host "==> Creating APIM integration in API Center ($($env:APIM_SERVICE))"
# Retry: new role assignments can take a minute or two to propagate.
for ($Attempt = 1; $Attempt -le 6; $Attempt++) {
  az apic integration create apim `
    --resource-group $env:RESOURCE_GROUP `
    --service-name $env:APIC_SERVICE `
    --integration-name "sync-from-$($env:APIM_SERVICE)" `
    --azure-apim $ApimId `
    -o table
  if ($LASTEXITCODE -eq 0) { break }
  if ($Attempt -eq 6) { throw "Failed to create APIM integration." }
  Write-Host "    Integration not ready (attempt $Attempt), retrying in 20s..."
  Start-Sleep -Seconds 20
}

Write-Host "==> All APIs currently in $($env:APIM_SERVICE) will now show up in the API Center catalog,"
Write-Host "    and stay in sync automatically as APIs are added/changed/removed in APIM."
