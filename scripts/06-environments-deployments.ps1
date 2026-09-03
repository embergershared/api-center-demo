# 06-environments-deployments.ps1 — model dev/test/prod environments and
# link the API's v2 to a deployment (e.g., an APIM gateway URL or App Service endpoint).
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

Write-Host "==> Creating environments: dev, test, prod"
$environments = @(
    @{ Id = $env:ENV_DEV; Title = "Dev"; Type = "development" }
    @{ Id = $env:ENV_TEST; Title = "Test"; Type = "testing" }
    @{ Id = $env:ENV_PROD; Title = "Prod"; Type = "production" }
)
foreach ($environment in $environments) {
    az apic environment create `
      --resource-group $env:RESOURCE_GROUP `
      --service-name $env:APIC_SERVICE `
      --environment-id $environment.Id `
      --title $environment.Title `
      --type $environment.Type `
      -o table
    if ($LASTEXITCODE -ne 0) { throw "Failed to create environment '$($environment.Id)'." }
}

Write-Host "==> Creating a deployment for v2 pointing at prod (example: an APIM gateway URL)"
$server = @{ runtimeUri = @("https://$($env:APIM_SERVICE).azure-api.net/fleet") } | ConvertTo-Json -Compress
az apic api deployment create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --deployment-id "prod-deployment" `
  --title "Production deployment" `
  --environment-id "/workspaces/default/environments/$($env:ENV_PROD)" `
  --definition-id "/workspaces/default/apis/$($env:API_ID)/versions/v2-0/definitions/openapi" `
  --server $server `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to create the production deployment." }

Write-Host "==> In the portal: open Fleet Vehicle API > Deployments to show the environment -> runtime URL mapping."
