# 07-lint-analysis.ps1 — run API analysis (Spectral-based linting) against the
# "messy" Legacy Depot Charger API to produce visible violations — the shift-left
# governance moment of the demo.
#
# Two ways to show this:
#   A) Register the analyzer/ruleset in API Center itself (custom linting rules
#      applied automatically whenever a definition is imported/updated).
#   B) Run spectral locally against the same file so the audience sees the
#      raw output immediately (faster for a live demo, no waiting on portal refresh).
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")
$SamplesDir = Join-Path $PSScriptRoot "../samples"

Write-Host "==> (A) Registering the messy API in the catalog so its analysis shows up in-portal"
$customProperties = '{
    "lifecycleStage": "development",
    "businessOwner": "Depot Operations Team"
  }'
az apic api create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id "legacy-depot-charger-api" `
  --title "Legacy Depot Charger API" `
  --type "rest" `
  --custom-properties $customProperties `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create the legacy depot charger API." }

az apic api version create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id "legacy-depot-charger-api" `
  --version-id "v1-0" `
  --title "v1" `
  --lifecycle-stage "development" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create the legacy API version 'v1'." }

az apic api definition create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id "legacy-depot-charger-api" `
  --version-id "v1-0" `
  --definition-id "openapi" `
  --title "OpenAPI 3.0" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create the legacy API definition." }

az apic api definition import-specification `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id "legacy-depot-charger-api" `
  --version-id "v1-0" `
  --definition-id "openapi" `
  --format "inline" `
  --specification '{"name":"openapi","version":"3.0.1"}' `
  --value "@$SamplesDir/legacy-depot-charger-messy.json" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to import the legacy OpenAPI specification." }

Write-Host ""
Write-Host "==> (B) Running Spectral locally for instant, visible lint output"
if (-not (Get-Command spectral -ErrorAction SilentlyContinue)) {
    Write-Host "Spectral CLI not found. Install once with: npm install -g @stoplight/spectral-cli"
} else {
    spectral lint "$SamplesDir/legacy-depot-charger-messy.json" --ruleset "$SamplesDir/.spectral.yaml"
}

Write-Host ""
Write-Host "==> Talk track: point out missing operationId, missing descriptions, non-semver version,"
Write-Host "    and missing error responses — this is the same ruleset API Center can enforce centrally"
Write-Host "    on every registered API, at import time or on a schedule."
