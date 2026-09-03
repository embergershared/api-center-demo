# 03-register-openapi-api.ps1 — register an API purely from an OpenAPI file upload
# (no APIM dependency), tag it with the custom metadata, and add v1 as a version/definition.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")
$SamplesDir = Join-Path $PSScriptRoot "../samples"

Write-Host "==> Creating the API entity in the catalog"
$customProperties = '{
    "lifecycleStage": "production",
    "businessOwner": "Fleet Platform Team <fleet-platform@contoso.com>",
    "complianceTag": ["internal-only"]
  }'
az apic api create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --title $env:API_TITLE `
  --type "rest" `
  --custom-properties $customProperties `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create API '$($env:API_ID)'." }

Write-Host "==> Creating version v1"
az apic api version create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --version-id "v1-0" `
  --title "v1" `
  --lifecycle-stage "deprecated" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create API version 'v1'." }

Write-Host "==> Creating definition for v1 and importing the OpenAPI spec"
az apic api definition create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --version-id "v1-0" `
  --definition-id "openapi" `
  --title "OpenAPI 3.0" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create the OpenAPI definition for version 'v1'." }

az apic api definition import-specification `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --version-id "v1-0" `
  --definition-id "openapi" `
  --format "inline" `
  --specification '{"name":"openapi","version":"3.0.1"}' `
  --value "@$SamplesDir/fleet-vehicle-v1.json" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to import the OpenAPI specification for version 'v1'." }

Write-Host "==> Registered. Now show in portal: search 'fleet vehicle', filter by lifecycleStage=production."
