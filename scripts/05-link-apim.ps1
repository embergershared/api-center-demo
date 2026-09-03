# 05-link-apim.ps1 — OPTIONAL: link an existing APIM instance so its APIs
# sync automatically into API Center (built-in sync, not a one-time import).
# Requires APIM_SERVICE to be set in 00-vars.ps1.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

if ([string]::IsNullOrEmpty($env:APIM_SERVICE)) {
    Write-Host "APIM_SERVICE is not set in 00-vars.ps1 — skipping. This step needs an existing APIM instance."
    exit 0
}

Write-Host "==> Fetching the APIM resource ID"
$ApimId = az apim show `
  --resource-group $env:APIM_RESOURCE_GROUP `
  --name $env:APIM_SERVICE `
  --query id -o tsv

Write-Host "==> Registering a link between API Center and APIM ($($env:APIM_SERVICE))"
az apic service link create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --link-name "apim-link-$($env:APIM_SERVICE)" `
  --azure-api-management-source-resource-id $ApimId `
  -o table

Write-Host "==> All APIs currently in $($env:APIM_SERVICE) will now show up in the API Center catalog,"
Write-Host "    and stay in sync automatically as APIs are added/changed/removed in APIM."
