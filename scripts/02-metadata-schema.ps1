# 02-metadata-schema.ps1 — define custom metadata fields for governance
# (lifecycle stage, business owner, compliance tag) and show they can be
# required/optional and assigned to APIs, environments, or deployments.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

# az is a .cmd on Windows: embedded double quotes are stripped and values with
# spaces (e.g. titles) get mangled. Pass each JSON schema via a temp file (@file).
# The metadata display name comes from the schema's "title" property.
$SchemaFile = Join-Path ([System.IO.Path]::GetTempPath()) "apic-metadata-schema.json"

# All fields are optional (required:false): the VS Code extension and 'az apic api register'
# can't set custom metadata, so required fields would block registration from those tools.
Write-Host "==> Creating custom metadata: lifecycleStage (enum, optional on APIs)"
$lifecycleSchema = '{
    "type": "string",
    "title": "Lifecycle stage",
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
[System.IO.File]::WriteAllText($SchemaFile, $lifecycleSchema)
az apic metadata create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --metadata-name "lifecycleStage" `
  --schema "@$SchemaFile" `
  --assignments '[{entity:api,required:false,deprecated:false}]' `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create lifecycleStage metadata." }

Write-Host "==> Creating custom metadata: businessOwner (string, optional on APIs)"
[System.IO.File]::WriteAllText($SchemaFile, '{"type": "string", "title": "Business owner"}')
az apic metadata create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --metadata-name "businessOwner" `
  --schema "@$SchemaFile" `
  --assignments '[{entity:api,required:false,deprecated:false}]' `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create businessOwner metadata." }

Write-Host "==> Creating custom metadata: complianceTag (enum, multi-select, on APIs)"
$complianceSchema = '{
    "type": "array",
    "title": "Compliance tag",
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
[System.IO.File]::WriteAllText($SchemaFile, $complianceSchema)
az apic metadata create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --metadata-name "complianceTag" `
  --schema "@$SchemaFile" `
  --assignments '[{entity:api,required:false,deprecated:false}]' `
  -o table
$CreateExitCode = $LASTEXITCODE
Remove-Item $SchemaFile -ErrorAction SilentlyContinue
if ($CreateExitCode -ne 0) { throw "Failed to create complianceTag metadata." }

Write-Host "==> Metadata schema created. These fields will show up as filter facets in the portal."
