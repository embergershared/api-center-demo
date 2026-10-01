[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deployment-context.ps1')
$values = Get-DeploymentEnvironment
Assert-DeploymentSubscription (Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID')
if ((Get-DeploymentValue $values 'AZURE_DEPLOYMENT_PROFILE') -ne 'full') {
    throw 'This demo requires a provisioned full profile. Run azd env refresh if outputs are stale.'
}

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

$agentName = 'azure-learn-managed'
$legacyAgentName = 'grid-maintenance-helper'
$connectionName = 'learn-docs-mcp-conn'
$projectEndpoint = Get-DeploymentValue $values 'AZURE_AI_PROJECT_ENDPOINT'
$projectName = Get-DeploymentValue $values 'AZURE_AI_PROJECT_NAME'
$foundryAccountName = Get-DeploymentValue $values 'AZURE_AI_FOUNDRY_NAME'
$chatDeployment = Get-DeploymentValue $values 'AZURE_OPENAI_CHAT_DEPLOYMENT'
$mcpToolUrl = Get-DeploymentValue $values 'MSLEARN_MCP_URL'
$subscriptionId = Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID'
$resourceGroup = Get-DeploymentValue $values 'AZURE_RESOURCE_GROUP'
$connectionId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$foundryAccountName/projects/$projectName/connections/$connectionName"
$agentBaseUri = "$($projectEndpoint.TrimEnd('/'))/agents"
$agentUri = "$agentBaseUri/${agentName}?api-version=v1"
$legacyAgentUri = "$agentBaseUri/${legacyAgentName}?api-version=v1"

if (-not $PSCmdlet.ShouldProcess($projectEndpoint, 'Create or update the Learn Docs MCP connection and demo agent')) { return }

Write-Host "==> Creating or updating the unauthenticated Foundry connection '$connectionName'"
$PSNativeCommandUseErrorActionPreference = $false
$connectionOutput = azd ai connection create $connectionName `
    --kind remote-tool `
    --target $mcpToolUrl `
    --auth-type none `
    --force `
    --project-endpoint $projectEndpoint `
    --output json `
    --no-prompt 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create RemoteTool connection '$connectionName' (azd exit code $LASTEXITCODE):$([Environment]::NewLine)$($connectionOutput -join [Environment]::NewLine)"
}

Write-Host "==> Removing the legacy Foundry agent '$legacyAgentName' when present"
$legacyAgent = Invoke-AzRestJson -Method 'GET' -Uri $legacyAgentUri -Resource 'https://ai.azure.com/' `
    -FailureMessage "Failed to query legacy agent '$legacyAgentName'" -IgnoreNotFound
if ($null -ne $legacyAgent) {
    Invoke-AzRestJson -Method 'DELETE' -Uri $legacyAgentUri -Resource 'https://ai.azure.com/' `
        -FailureMessage "Failed to delete legacy agent '$legacyAgentName'"
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
        instructions = 'Answer Azure questions using the Microsoft Learn MCP tool. Cite the Microsoft Learn documentation used in the answer.'
        tools = @(
            @{
                type = 'mcp'
                server_label = 'microsoft-learn'
                server_url = $mcpToolUrl
                require_approval = 'never'
                project_connection_id = $connectionId
            }
        )
    }
}

Write-Host "==> Creating Foundry agent '$agentName'"
$agent = Invoke-AzRestJson -Method 'POST' -Uri "${agentBaseUri}?api-version=v1" -Resource 'https://ai.azure.com/' `
    -Body $agentBody -FailureMessage "Failed to create agent '$agentName'"
if ($null -eq $agent -or [string]::IsNullOrWhiteSpace($agent.name)) {
    throw "Azure did not return a valid agent payload for '$agentName'."
}

Write-Host "==> Learn Docs MCP is configured with no authentication at $mcpToolUrl."
Write-Host "    Do not select Microsoft Entra or OAuth for this connection; those modes require an audience."
