# 02-metadata-schema.ps1 — define custom metadata fields for governance
# (lifecycle stage, business owner, compliance tag) and show they can be
# required/optional and assigned to APIs, environments, or deployments.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")
. (Join-Path $PSScriptRoot 'demo-cli.ps1')

function Set-DemoMetadata {
    param(
        [string] $Name,
        [string] $Schema,
        [bool] $Required
    )

    $assignments = ConvertTo-Json -InputObject @(
        @{ entity = 'api'; required = $Required; deprecated = $false }
    )
    Invoke-DemoAz -Arguments @(
        'apic', 'metadata', 'create',
        '--resource-group', $env:RESOURCE_GROUP,
        '--service-name', $env:APIC_SERVICE,
        '--metadata-name', $Name,
        '-o', 'table'
    ) -JsonArguments @{ '--schema' = $Schema; '--assignments' = $assignments } `
        -FailureMessage "Failed to create $Name metadata" | Out-Host
}

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
Set-DemoMetadata -Name 'lifecycleStage' -Schema $lifecycleSchema -Required $false

Write-Host "==> Creating custom metadata: businessOwner (string, optional on APIs)"
Set-DemoMetadata -Name 'businessOwner' -Schema '{"type": "string", "title": "Business owner"}' -Required $false

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
        {"const": "NERC-CIP"},
        {"const": "internal-only"}
      ]
    }
  }'
Set-DemoMetadata -Name 'complianceTag' -Schema $complianceSchema -Required $false

Write-Host "==> Creating custom metadata: department (optional on APIs)"
Set-DemoMetadata -Name 'department' -Schema '{"type": "string", "title": "Department"}' -Required $false

Write-Host "==> Metadata schema created. These fields will show up as filter facets in the portal."
Write-Host "NERC-CIP is a catalog classification only, not evidence of regulatory compliance."
