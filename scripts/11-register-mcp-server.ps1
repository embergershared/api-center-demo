# 11-register-mcp-server.ps1 — register the deployed Grid Tools MCP server in
# API Center's MCP registry using the same ARM API as provision-catalog.ps1.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-vars.ps1')
. (Join-Path $PSScriptRoot 'demo-cli.ps1')

$gridMcpAppUrl = Get-DeploymentValue $deploymentValues 'GRID_MCP_APP_URL'
$gridMcpAppName = Get-DeploymentValue $deploymentValues 'GRID_MCP_APP_NAME'
$mcpRuntimeUrl = "$($gridMcpAppUrl.TrimEnd('/'))/mcp"
$customProperties = @{
    lifecycleStage = 'production'
    businessOwner = 'Grid Operations Team <grid-ops@contoso.com>'
    complianceTag = @('NERC-CIP')
}

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

Assert-DemoContainerAppDeployed -AppName $gridMcpAppName -ServiceName 'grid-tools-mcp'
$workspace = "$($env:APIC_RESOURCE_ID)/workspaces/default"
$apiId = "$workspace/apis/grid-tools-mcp"
$versionId = 'v1-0'
$definitionId = "$apiId/versions/$versionId/definitions/mcp"
$deploymentId = "$apiId/deployments/prod"

Write-Host "==> Ensuring the production environment record exists for remote MCP registration"
$null = Invoke-CatalogRest PUT "$workspace/environments/$($env:ENV_PROD)" @{
    properties = @{ title = 'Prod'; kind = 'production' }
}

Write-Host "==> Registering MCP server '$gridMcpAppName' at $mcpRuntimeUrl"
$null = Invoke-CatalogRest PUT $apiId @{
    properties = @{
        title = 'Grid Tools MCP Server'
        kind = 'mcp'
        summary = 'Synthetic grid-maintenance MCP tools backed by the deployed GridTools.Mcp Container App.'
        description = "Remote MCP server hosted by '$gridMcpAppName' for demo-safe substation lookup and health checks."
        lifecycleStage = 'production'
        customProperties = $customProperties
    }
}
$null = Invoke-CatalogRest PUT "$apiId/versions/$versionId" @{
    properties = @{ title = 'v1'; lifecycleStage = 'production' }
}
$null = Invoke-CatalogRest PUT $definitionId @{
    properties = @{ title = 'MCP'; description = 'Remote MCP server using streamable HTTP at /mcp.' }
}
$null = Invoke-CatalogRest PUT $deploymentId @{
    properties = @{
        title = 'Grid Tools MCP production'
        environmentId = "/workspaces/default/environments/$($env:ENV_PROD)"
        definitionId = "/workspaces/default/apis/grid-tools-mcp/versions/$versionId/definitions/mcp"
        server = @{ runtimeUri = @($mcpRuntimeUrl) }
    }
}

$api = Invoke-CatalogRest GET $apiId
$deployment = Invoke-CatalogRest GET $deploymentId
if ($api.properties.kind -cne 'mcp' -or
    $api.properties.apiSourceId -or $deployment.properties.apiSourceId -or
    $deployment.properties.definitionId -cne "/workspaces/default/apis/grid-tools-mcp/versions/$versionId/definitions/mcp" -or
    $deployment.properties.environmentId -cne "/workspaces/default/environments/$($env:ENV_PROD)" -or
    @($deployment.properties.server.runtimeUri).Count -ne 1 -or
    $deployment.properties.server.runtimeUri[0] -cne $mcpRuntimeUrl) {
    throw "Catalog readback failed for 'grid-tools-mcp'; expected an independent MCP asset with its production /mcp runtime URL."
}

Write-Host "==> Registered. In the portal, open API Center > Assets and the MCP registry experience to show 'Grid Tools MCP Server' beside the REST APIs."
