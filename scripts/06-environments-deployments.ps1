# 06-environments-deployments.ps1 — model dev/test/prod environments and
# link the API's v2 to a deployment (e.g., an APIM gateway URL or App Service endpoint).
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")
. (Join-Path $PSScriptRoot 'demo-cli.ps1')

Write-Host "==> Creating environments: dev, test, prod"
Write-Host '    These are API Center catalog records, not separate azd environments or provisioned runtimes.'
$environments = @(
    @{ Id = $env:ENV_DEV; Title = "Dev"; Type = "development" }
    @{ Id = $env:ENV_TEST; Title = "Test"; Type = "testing" }
    @{ Id = $env:ENV_PROD; Title = "Prod"; Type = "production" }
)
foreach ($environment in $environments) {
    Invoke-DemoAz -Arguments @(
        'apic', 'environment', 'create',
        '--resource-group', $env:RESOURCE_GROUP,
        '--service-name', $env:APIC_SERVICE,
        '--environment-id', $environment.Id,
        '--title', $environment.Title,
        '--type', $environment.Type,
        '-o', 'table'
    ) -FailureMessage "Failed to create environment '$($environment.Id)'"
}

Write-Host "==> Creating a deployment for v2 pointing at prod (example: an APIM gateway URL)"
$server = @{ runtimeUri = @("$($env:APIM_GATEWAY_URL.TrimEnd('/'))/fleet") } | ConvertTo-Json -Compress
Invoke-DemoAz -Arguments @(
    'apic', 'api', 'deployment', 'create',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--api-id', $env:API_ID,
    '--deployment-id', 'prod-deployment',
    '--title', 'Production deployment',
    '--environment-id', "/workspaces/default/environments/$($env:ENV_PROD)",
    '--definition-id', "/workspaces/default/apis/$($env:API_ID)/versions/v2-0/definitions/openapi",
    '-o', 'table'
) -JsonArguments @{ '--server' = $server } `
    -FailureMessage 'Failed to create the production deployment'

Write-Host "==> In the portal: open Fleet Vehicle API > Deployments to show the environment -> runtime URL mapping."
Write-Host '    The /fleet route contains the imported specification; no live Fleet backend is implemented.'
