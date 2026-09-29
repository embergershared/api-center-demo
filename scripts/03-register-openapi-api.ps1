# 03-register-openapi-api.ps1 — register an API purely from an OpenAPI file upload
# (no APIM dependency), tag it with the custom metadata, and add v1 as a version/definition.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")
. (Join-Path $PSScriptRoot 'demo-cli.ps1')
$SamplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'samples'
$specificationPath = Join-Path $SamplesDir 'fleet-vehicle-v1.json'

Write-Host "==> Creating the API entity in the catalog"
$customProperties = '{
    "lifecycleStage": "production",
    "businessOwner": "Fleet Platform Team <fleet-platform@contoso.com>",
    "complianceTag": ["internal-only"]
  }'
Invoke-DemoAz -Arguments @(
    'apic', 'api', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', $env:API_ID,
    '--title', $env:API_TITLE,
    '--type', 'rest',
    '-o', 'table'
) -JsonArguments @{ '--custom-properties' = $customProperties } `
    -FailureMessage "Failed to create API '$($env:API_ID)'"

Write-Host "==> Creating version v1"
Invoke-DemoAz -Arguments @(
    'apic', 'api', 'version', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', $env:API_ID,
    '--version-id', 'v1-0',
    '--title', 'v1',
    '--lifecycle-stage', 'deprecated',
    '-o', 'table'
) -FailureMessage "Failed to create API version 'v1'"

Write-Host "==> Creating definition for v1 and importing the OpenAPI spec"
Invoke-DemoAz -Arguments @(
    'apic', 'api', 'definition', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', $env:API_ID,
    '--version-id', 'v1-0',
    '--definition-id', 'openapi',
    '--title', 'OpenAPI 3.0',
    '-o', 'table'
) -FailureMessage "Failed to create the OpenAPI definition for version 'v1'"

Invoke-DemoAz -Arguments @(
    'apic', 'api', 'definition', 'import-specification',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', $env:API_ID,
    '--version-id', 'v1-0',
    '--definition-id', 'openapi',
    '--format', 'inline',
    '--value', "@$specificationPath",
    '-o', 'table'
) -JsonArguments @{ '--specification' = '{"name":"openapi","version":"3.0.1"}' } `
    -FailureMessage "Failed to import the OpenAPI specification for version 'v1'"

Write-Host "==> Registered. Now show in portal: search 'fleet vehicle', filter by lifecycleStage=production."
