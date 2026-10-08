$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deployment-context.ps1')
. (Join-Path $PSScriptRoot 'demo-cli.ps1')

function Set-ProvisionedCatalog {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Values)

    $subscription = Get-DeploymentValue $Values 'AZURE_SUBSCRIPTION_ID'
    Assert-DeploymentSubscription $subscription
    $serviceId = Get-DeploymentValue $Values 'APIC_RESOURCE_ID'
    $apimId = Get-DeploymentValue $Values 'APIM_RESOURCE_ID'
    $gateway = (Get-DeploymentValue $Values 'APIM_GATEWAY_URL').TrimEnd('/')
    $mcpUrl = Get-DeploymentValue $Values 'MSLEARN_MCP_URL'
    $profile = Get-DeploymentValue $Values 'AZURE_DEPLOYMENT_PROFILE'
    if ($profile -cnotin @('core', 'full')) { throw "Unknown deployment profile '$profile'." }
    if ($mcpUrl -cne "$gateway/learn-mcp/mcp") { throw 'Learn MCP URL must point at the gateway /learn-mcp/mcp endpoint.' }
    $workspace = "$serviceId/workspaces/default"
    $root = Split-Path -Parent $PSScriptRoot
    $cliScope = @('--subscription', $subscription, '--resource-group',
        (Get-DeploymentValue $Values 'AZURE_RESOURCE_GROUP'), '--service-name',
        (Get-DeploymentValue $Values 'APIC_SERVICE'))

    function Invoke-CatalogRest {
        param([string] $Method, [string] $Id, [object] $Body)
        $arguments = @('rest', '--method', $Method, '--url',
            "https://management.azure.com${Id}?api-version=2024-06-01-preview", '--output', 'json')
        $jsonArguments = @{}
        if ($null -ne $Body) { $jsonArguments['--body'] = ConvertTo-Json -InputObject $Body -Depth 30 -Compress }
        $result = Invoke-DemoAz -Arguments $arguments -JsonArguments $jsonArguments -FailureMessage "Catalog $Method failed: $Id"
        if ($result) { return ($result -join [Environment]::NewLine) | ConvertFrom-Json }
    }

    $environmentId = "$workspace/environments/managed-apim"
    $null = Invoke-CatalogRest PUT $environmentId @{
        properties = @{
            title = 'API Management (independently managed)'
            kind = 'production'
            server = @{ type = 'azure-api-management'; managementPortalUri = @("https://portal.azure.com/#resource$apimId") }
        }
    }
    $entries = @(
        @{ id = 'managed-fleet-vehicle'; title = 'Fleet Vehicle API (managed)'; kind = 'rest'
            url = "$gateway/fleet"; spec = (Join-Path $root 'samples\fleet-vehicle-v2.json') }
        @{ id = 'managed-mslearn-mcp'; title = 'Microsoft Learn Docs (MCP passthrough, managed)'; kind = 'mcp'
            url = $mcpUrl; spec = $null }
    )
    if ($profile -eq 'full') {
        $entries += @{ id = 'managed-utility-ai'; title = 'Utility AI demonstration (managed)'; kind = 'rest'
            url = "$gateway/ai"; spec = (Join-Path $root 'infra\modules\api-management\openapi.json') }
    }
    $versionId = 'v1-0-0'
    foreach ($entry in $entries) {
        $apiId = "$workspace/apis/$($entry.id)"
        $null = Invoke-CatalogRest PUT $apiId @{
            properties = @{
                title = $entry.title
                kind = $entry.kind
                description = 'Provisioned independently by azd. Use this entry instead of the synchronized copy for demo runtime URLs.'
                lifecycleStage = 'design'
                customProperties = @{ lifecycleStage = 'design'; businessOwner = 'API Center Demo' }
            }
        }
        $null = Invoke-CatalogRest PUT "$apiId/versions/$versionId" @{
            properties = @{ title = 'Current demo'; lifecycleStage = 'design' }
        }
        $definitionId = "$apiId/versions/$versionId/definitions/default"
        $null = Invoke-CatalogRest PUT $definitionId @{ properties = @{ title = 'Default' } }
        if ($entry.spec) {
            $specification = Get-Content -LiteralPath $entry.spec -Raw | ConvertFrom-Json
            $null = Invoke-DemoAz -Arguments (@('apic', 'api', 'definition', 'import-specification') + $cliScope + @(
                '--api-id', $entry.id, '--version-id', $versionId, '--definition-id', 'default',
                '--format', 'inline', '--value', "@$($entry.spec)", '--output', 'none'
            )) -JsonArguments @{ '--specification' = (@{ name = 'openapi'; version = $specification.openapi } | ConvertTo-Json -Compress) } `
                -FailureMessage "Failed to import specification for $($entry.id)"
        }
        $deploymentId = "$apiId/deployments/managed"
        $null = Invoke-CatalogRest PUT $deploymentId @{
            properties = @{
                title = 'Managed APIM endpoint'
                environmentId = '/workspaces/default/environments/managed-apim'
                definitionId = "/workspaces/default/apis/$($entry.id)/versions/$versionId/definitions/default"
                server = @{ runtimeUri = @($entry.url) }
            }
        }
        $actual = Invoke-CatalogRest GET $deploymentId
        $api = Invoke-CatalogRest GET $apiId
        if ($actual.properties.apiSourceId -or $api.properties.apiSourceId -or
            @($actual.properties.server.runtimeUri).Count -ne 1 -or
            $actual.properties.server.runtimeUri[0] -cne $entry.url) {
            throw "Catalog readback failed for $($entry.id); entry must be independent and retain its exact runtime URL."
        }
        Write-Host "Provisioned $($entry.title): $($entry.url)"
    }

    Write-Host 'Independent catalog entries configured. The next postprovision step verifies the APIM synchronization link.'
}

if ($MyInvocation.InvocationName -ne '.') {
    Set-ProvisionedCatalog -Values (Get-DeploymentEnvironment)
}
