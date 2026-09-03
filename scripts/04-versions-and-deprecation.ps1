# 04-versions-and-deprecation.ps1 — add v2 alongside v1, mark v1 deprecated,
# demonstrating version lifecycle tracking in the catalog.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")
$SamplesDir = Join-Path $PSScriptRoot "../samples"

Write-Host "==> Creating version v2 (current/production)"
az apic api version create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --version-id "v2-0" `
  --title "v2" `
  --lifecycle-stage "production" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create API version 'v2'." }

az apic api definition create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --version-id "v2-0" `
  --definition-id "openapi" `
  --title "OpenAPI 3.0" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create the OpenAPI definition for version 'v2'." }

az apic api definition import-specification `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --version-id "v2-0" `
  --definition-id "openapi" `
  --format "inline" `
  --specification '{"name":"openapi","version":"3.0.1"}' `
  --value "@$SamplesDir/fleet-vehicle-v2.json" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to import the OpenAPI specification for version 'v2'." }

Write-Host "==> Explicitly re-confirming v1 lifecycle = deprecated (for the demo narrative)"
az apic api version update `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --version-id "v1-0" `
  --lifecycle-stage "deprecated" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to update API version 'v1'." }

Write-Host "==> In the portal: show API 'Fleet Vehicle API' with two versions, v1 badged Deprecated, v2 Production."
