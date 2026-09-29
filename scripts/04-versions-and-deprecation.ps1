# 04-versions-and-deprecation.ps1 — add v2 alongside v1, mark v1 deprecated,
# demonstrating version lifecycle tracking in the catalog.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")
. (Join-Path $PSScriptRoot 'demo-cli.ps1')
$SamplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'samples'
$specificationPath = Join-Path $SamplesDir 'fleet-vehicle-v2.json'

Write-Host "==> Creating version v2 (current/production)"
Invoke-DemoAz -Arguments @(
    'apic', 'api', 'version', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', $env:API_ID,
    '--version-id', 'v2-0',
    '--title', 'v2',
    '--lifecycle-stage', 'production',
    '-o', 'table'
) -FailureMessage "Failed to create API version 'v2'"

Invoke-DemoAz -Arguments @(
    'apic', 'api', 'definition', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', $env:API_ID,
    '--version-id', 'v2-0',
    '--definition-id', 'openapi',
    '--title', 'OpenAPI 3.0',
    '-o', 'table'
) -FailureMessage "Failed to create the OpenAPI definition for version 'v2'"

Invoke-DemoAz -Arguments @(
    'apic', 'api', 'definition', 'import-specification',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', $env:API_ID,
    '--version-id', 'v2-0',
    '--definition-id', 'openapi',
    '--format', 'inline',
    '--value', "@$specificationPath",
    '-o', 'table'
) -JsonArguments @{ '--specification' = '{"name":"openapi","version":"3.0.1"}' } `
    -FailureMessage "Failed to import the OpenAPI specification for version 'v2'"

Write-Host "==> Explicitly re-confirming v1 lifecycle = deprecated (for the demo narrative)"
Invoke-DemoAz -Arguments @(
    'apic', 'api', 'version', 'update',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', $env:API_ID,
    '--version-id', 'v1-0',
    '--lifecycle-stage', 'deprecated',
    '-o', 'table'
) -FailureMessage "Failed to update API version 'v1'"

Write-Host "==> Importing Fleet Vehicle API v2 into API Management at /fleet"
Invoke-DemoAz -Arguments @(
    'apim', 'api', 'import',
    '--resource-group', $env:APIM_RESOURCE_GROUP,
    '--service-name', $env:APIM_SERVICE,
    '--api-id', $env:API_ID,
    '--path', 'fleet',
    '--display-name', $env:API_TITLE,
    '--specification-format', 'OpenAPI',
    '--specification-path', $specificationPath,
    '-o', 'table'
) -FailureMessage 'Failed to import Fleet Vehicle API into API Management'

Write-Host "==> In the portals: show API Center version history and the APIM-hosted /fleet API."
Write-Host '    This imports the Fleet specification and route, not a working Fleet backend.'
Write-Host '    The Bicep-managed /ai API is separate and is not modified by this script.'
