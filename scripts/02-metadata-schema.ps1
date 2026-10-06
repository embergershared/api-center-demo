# 02-metadata-schema.ps1 — define custom metadata fields for governance
# (lifecycle stage, business owner, compliance tag) and show they can be
# required/optional and assigned to APIs, environments, or deployments.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

# az is a .cmd on Windows: newlines truncate the command line and embedded
# double quotes are stripped. Pass JSON as a single line with escaped quotes.
$PSNativeCommandArgumentPassing = 'Legacy'
function ConvertTo-AzJsonArg([string]$Json) {
  ($Json | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10) -replace '"', '\"'
}

Write-Host "==> Creating custom metadata: lifecycleStage (enum, required on APIs)"
$lifecycleSchema = '{
    "type": "string",
    "oneOf": [
      {"const": "design"},
      {"const": "development"},
      {"const": "testing"},
      {"const": "preview"},
      {"const": "production"},
      {"const": "deprecated"},
      {"const": "retired"}
    ]
  }'
az apic metadata create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --metadata-name "lifecycleStage" `
  --schema (ConvertTo-AzJsonArg $lifecycleSchema) `
  --assignments '[{entity:api,required:true,deprecated:false}]' `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create lifecycleStage metadata." }

Write-Host "==> Creating custom metadata: businessOwner (string, required on APIs)"
az apic metadata create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --metadata-name "businessOwner" `
  --schema (ConvertTo-AzJsonArg '{"type": "string"}') `
  --assignments '[{entity:api,required:true,deprecated:false}]' `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create businessOwner metadata." }

Write-Host "==> Creating custom metadata: complianceTag (enum, multi-select, on APIs)"
$complianceSchema = '{
    "type": "array",
    "items": {
      "type": "string",
      "oneOf": [
        {"const": "PCI"},
        {"const": "HIPAA"},
        {"const": "GDPR"},
        {"const": "SOC2"},
        {"const": "internal-only"}
      ]
    }
  }'
az apic metadata create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --metadata-name "complianceTag" `
  --schema (ConvertTo-AzJsonArg $complianceSchema) `
  --assignments '[{entity:api,required:false,deprecated:false}]' `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create complianceTag metadata." }

Write-Host "==> Metadata schema created. These fields will show up as filter facets in the portal."
