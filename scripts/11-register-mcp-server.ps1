# 11-register-mcp-server.ps1 — register the deployed Grid Tools MCP server in
# API Center's MCP registry. This depends on a preview apic-extension surface.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-vars.ps1')
. (Join-Path $PSScriptRoot 'demo-cli.ps1')

$gridMcpAppUrl = Get-DeploymentValue $deploymentValues 'GRID_MCP_APP_URL'
$gridMcpAppName = Get-DeploymentValue $deploymentValues 'GRID_MCP_APP_NAME'
$mcpRuntimeUrl = "$($gridMcpAppUrl.TrimEnd('/'))/mcp"
$customProperties = '{
    "lifecycleStage": "production",
    "businessOwner": "Grid Operations Team <grid-ops@contoso.com>",
    "complianceTag": ["NERC-CIP", "grid-operational-data"]
  }'

Write-Host '==> Verifying the API Center plan supports the MCP registry'
$sku = Invoke-DemoAz -Arguments @(
    'resource', 'show',
    '--ids', $env:APIC_RESOURCE_ID,
    '--api-version', '2024-06-01-preview',
    '--query', 'sku.name',
    '--output', 'tsv'
) -FailureMessage "Failed to read the current plan for API Center '$($env:APIC_SERVICE)'"
if ($sku -ne 'Standard') {
    throw "API Center '$($env:APIC_SERVICE)' must be on the Standard plan before you can register MCP servers. Current plan: '$sku'. Upgrade it in the portal, then run 'azd env set API_CENTER_SKU Standard'."
}

Write-Host '==> Probing the installed apic-extension for MCP server support'
$extensionVersion = $null
$PSNativeCommandUseErrorActionPreference = $false
$extensionDetails = az extension show --name apic-extension --only-show-errors 2>&1
if ($LASTEXITCODE -eq 0) {
    try {
        $extensionVersion = (($extensionDetails -join [Environment]::NewLine) | ConvertFrom-Json).version
    }
    catch {
        $extensionVersion = $null
    }
}

$probeOutput = az apic mcp-server --help 2>&1
if ($LASTEXITCODE -ne 0) {
    $versionNote = if ([string]::IsNullOrWhiteSpace($extensionVersion)) {
        'The apic-extension is not installed in this shell.'
    }
    else {
        "Installed apic-extension version: $extensionVersion."
    }

    throw "The installed Azure CLI does not expose 'az apic mcp-server'. $versionNote Install or upgrade preview support with: az extension add --name apic-extension --upgrade --allow-preview true`n$($probeOutput -join [Environment]::NewLine)"
}

# This preview command shape is intentionally aligned with the portal fields for
# a remote MCP server registration. The runtime URL uses the streamable HTTP
# endpoint exposed by GridTools.Mcp at /mcp.
Write-Host "==> Ensuring the production environment record exists for remote MCP registration"
Invoke-DemoAz -Arguments @(
    'apic', 'environment', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--environment-id', $env:ENV_PROD,
    '--title', 'Prod',
    '--type', 'production',
    '-o', 'table'
) -FailureMessage "Failed to create environment '$($env:ENV_PROD)'"

Write-Host "==> Registering MCP server '$gridMcpAppName' at $mcpRuntimeUrl"
Invoke-DemoAz -Arguments @(
    'apic', 'mcp-server', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--mcp-server-id', 'grid-tools-mcp',
    '--title', 'Grid Tools MCP Server',
    '--summary', 'Synthetic grid-maintenance MCP tools backed by the deployed GridTools.Mcp App Service.',
    '--description', "Remote MCP server hosted by '$gridMcpAppName' for demo-safe substation lookup and health checks.",
    '--version-id', 'v1-0',
    '--version-title', 'v1',
    '--lifecycle-stage', 'production',
    '--remote-url', $mcpRuntimeUrl,
    '--environment-id', $env:ENV_PROD,
    '-o', 'table'
) -JsonArguments @{ '--custom-properties' = $customProperties } `
    -FailureMessage "Failed to register MCP server 'grid-tools-mcp'"

Write-Host "==> Registered. In the portal, open API Center > Assets and the MCP registry experience to show 'Grid Tools MCP Server' beside the REST APIs."
