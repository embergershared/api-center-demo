# 06-environments-deployments.ps1 — model dev/test/prod environments and
# link the API's v2 to a deployment (e.g., an APIM gateway URL or App Service endpoint).
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

Write-Host "==> Creating environments: dev, test, prod"
$Environments = @(
    @{ Id = $env:ENV_DEV;  Title = "Dev";  Type = "development" }
    @{ Id = $env:ENV_TEST; Title = "Test"; Type = "testing" }
    @{ Id = $env:ENV_PROD; Title = "Prod"; Type = "production" }
)
foreach ($Environment in $Environments) {
    az apic environment create `
      --resource-group $env:RESOURCE_GROUP `
      --service-name $env:APIC_SERVICE `
      --environment-id $Environment.Id `
      --title $Environment.Title `
      --type $Environment.Type `
      -o table
    if ($LASTEXITCODE -ne 0) { throw "Failed to create environment '$($Environment.Id)'." }
}

Write-Host "==> Creating a deployment for v2 pointing at prod (example: an APIM gateway URL)"
# Pass JSON via file: az.cmd strips embedded double quotes from inline JSON.
$ServerFile = Join-Path ([System.IO.Path]::GetTempPath()) "apic-deployment-server.json"
[System.IO.File]::WriteAllText($ServerFile, '{"runtimeUri":["https://contoso-apim.azure-api.net/fleet"]}')
az apic api deployment create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --deployment-id "prod-deployment" `
  --title "Production deployment" `
  --environment-id "/workspaces/default/environments/$($env:ENV_PROD)" `
  --definition-id "/workspaces/default/apis/$($env:API_ID)/versions/v2-0/definitions/openapi" `
  --server "@$ServerFile" `
  -o table
$CreateExitCode = $LASTEXITCODE
Remove-Item $ServerFile -ErrorAction SilentlyContinue
if ($CreateExitCode -ne 0) { throw "Failed to create the production deployment." }

Write-Host "==> In Azure portal: open Fleet Vehicle API > Deployments to show the environment -> runtime URL mapping."
