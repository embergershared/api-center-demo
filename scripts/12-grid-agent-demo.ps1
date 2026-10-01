[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deployment-context.ps1')
$values = Get-DeploymentEnvironment
Assert-DeploymentSubscription (Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID')
if ((Get-DeploymentValue $values 'AZURE_DEPLOYMENT_PROFILE') -ne 'full') {
    throw 'This demo requires a provisioned full profile. Run azd env refresh if outputs are stale.'
}
. (Join-Path $PSScriptRoot '00-vars.ps1')
. (Join-Path $PSScriptRoot 'demo-cli.ps1')

function Invoke-AzRestJson {
    param(
        [Parameter(Mandatory)][string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        [Parameter(Mandatory)][string] $Resource,
        [object] $Body,
        [string] $FailureMessage = 'Azure REST call failed',
        [switch] $IgnoreNotFound
    )

    $temporaryBodyPath = $null
    try {
        $arguments = @('rest', '--resource', $Resource, '--method', $Method, '--uri', $Uri, '--only-show-errors')
        if ($null -ne $Body) {
            $temporaryBodyPath = [System.IO.Path]::GetTempFileName()
            $Body | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporaryBodyPath -Encoding utf8
            $arguments += @('--body', "@$temporaryBodyPath")
        }

        $PSNativeCommandUseErrorActionPreference = $false
        $output = az @arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            $joined = $output -join [Environment]::NewLine
            if ($IgnoreNotFound -and $joined -match '404|Not\s*Found|not_found') {
                return $null
            }

            throw "$FailureMessage (Azure CLI exit code $LASTEXITCODE):$([Environment]::NewLine)$joined"
        }

        if ($output.Count -eq 0) {
            return $null
        }

        return ($output -join [Environment]::NewLine) | ConvertFrom-Json -Depth 50
    }
    finally {
        if ($null -ne $temporaryBodyPath) {
            Remove-Item -LiteralPath $temporaryBodyPath -Force -ErrorAction SilentlyContinue
        }
    }
}

$agentName = 'grid-maintenance-agent'
$agentTitle = 'Grid Maintenance Agent'
$toolConnectionName = 'grid-tools-mcp-conn'
$projectEndpoint = Get-DeploymentValue $values 'AZURE_AI_PROJECT_ENDPOINT'
$projectName = Get-DeploymentValue $values 'AZURE_AI_PROJECT_NAME'
$foundryAccountName = Get-DeploymentValue $values 'AZURE_AI_FOUNDRY_NAME'
$chatDeployment = Get-DeploymentValue $values 'AZURE_OPENAI_CHAT_DEPLOYMENT'
$gridMcpAppUrl = Get-DeploymentValue $values 'GRID_MCP_APP_URL'
$mcpToolUrl = "$($gridMcpAppUrl.TrimEnd('/'))/mcp"
$subscriptionId = Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID'
$resourceGroup = Get-DeploymentValue $values 'AZURE_RESOURCE_GROUP'
$connectionUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$foundryAccountName/projects/$projectName/connections/${toolConnectionName}?api-version=2025-10-01-preview"
$agentBaseUri = "$($projectEndpoint.TrimEnd('/'))/agents"
$agentUri = "$agentBaseUri/${agentName}?api-version=v1"

if (-not $PSCmdlet.ShouldProcess($projectEndpoint, 'Create or update the Grid Maintenance Agent and its MCP tool connection')) { return }

# The MCP tool schema uses definition.tools[].project_connection_id to bind the
# agent-side tool entry to the project-level RemoteTool connection.
$connectionBody = @{
    properties = @{
        category = 'RemoteTool'
        authType = 'None'
        target = $mcpToolUrl
        isSharedToAll = $true
        metadata = @{
            ApiType = 'MCP'
            Transport = 'streamable'
        }
    }
}

Write-Host "==> Creating or updating the Foundry project connection '$toolConnectionName'"
$connection = Invoke-AzRestJson -Method 'PUT' -Uri $connectionUri -Resource 'https://management.azure.com/' `
    -Body $connectionBody -FailureMessage "Failed to create RemoteTool connection '$toolConnectionName'"
if ($null -eq $connection -or [string]::IsNullOrWhiteSpace($connection.id)) {
    throw "Azure did not return an id for RemoteTool connection '$toolConnectionName'."
}

Write-Host "==> Replacing the existing Foundry agent definition for '$agentName' when present"
$existingAgent = Invoke-AzRestJson -Method 'GET' -Uri $agentUri -Resource 'https://ai.azure.com/' `
    -FailureMessage "Failed to query agent '$agentName'" -IgnoreNotFound
if ($null -ne $existingAgent) {
    Invoke-AzRestJson -Method 'DELETE' -Uri $agentUri -Resource 'https://ai.azure.com/' `
        -FailureMessage "Failed to delete the existing agent '$agentName'"
}

$agentBody = @{
    name = $agentName
    definition = @{
        kind = 'prompt'
        model = $chatDeployment
        instructions = @'
You are the fictional Grid Maintenance Agent for a software demonstration.
Use the available MCP tools to look up synthetic substation status and summarize maintenance history in a concise, non-operational way.
Never imply you have real outage data, live operational authority, switching instructions, or safety guidance.
If a request would require real operational data, explain that the demo only contains synthetic training data.
'@
        tools = @(
            @{
                type = 'mcp'
                server_label = 'grid-tools'
                server_url = $mcpToolUrl
                require_approval = 'never'
                project_connection_id = $connection.id
                allowed_tools = @('list_substations', 'get_substation_health')
            }
        )
    }
}

Write-Host "==> Creating Foundry agent '$agentTitle'"
$agent = Invoke-AzRestJson -Method 'POST' -Uri "${agentBaseUri}?api-version=v1" -Resource 'https://ai.azure.com/' `
    -Body $agentBody -FailureMessage "Failed to create agent '$agentName'"
if ($null -eq $agent -or [string]::IsNullOrWhiteSpace($agent.name)) {
    throw "Azure did not return a valid agent payload for '$agentName'."
}

# We intentionally reuse the APIM-synchronized `utility-ai` API Center entry
# instead of creating a second catalog record. The gateway URL is the actual
# governed runtime endpoint; the Foundry agent itself doesn't expose a separate
# AI-Gateway-fronted HTTP surface in this repo.
Write-Host "==> Verifying the AI gateway catalog entry already exists in API Center"
$catalogJson = Invoke-DemoAz -Arguments @(
    'apic', 'api', 'list',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--query', "[?name=='utility-ai'].{name:name,title:title}",
    '--output', 'json'
) -FailureMessage 'Failed to query the API Center catalog for the Utility AI entry'
$catalogEntries = ($catalogJson -join [Environment]::NewLine) | ConvertFrom-Json -NoEnumerate
if ($catalogEntries -isnot [array]) {
    $catalogEntries = @($catalogEntries)
}

if ($catalogEntries.Count -eq 0) {
    Write-Warning "The APIM-synchronized 'utility-ai' entry is not visible in API Center yet. Run script 05 if needed and allow synchronization time before the demo."
}
else {
    $catalogEntries | Format-Table name, title | Out-Host
    Write-Host "    Use API Center to show the synchronized Utility AI gateway entry that fronts the Grid Maintenance Agent's model calls."
}

Write-Host "==> Grid Maintenance Agent ready in Foundry. Its governed runtime path remains the synced Utility AI API Center entry."
