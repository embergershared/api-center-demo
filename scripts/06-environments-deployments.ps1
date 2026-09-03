# 06-environments-deployments.ps1 — model dev/test/prod environments and
# link the API's v2 to a deployment (e.g., an APIM gateway URL or App Service endpoint).
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

Write-Host "==> Creating environments: dev, test, prod"
foreach ($Env in @($env:ENV_DEV, $env:ENV_TEST, $env:ENV_PROD)) {
    $Title = $Env.Substring(0,1).ToUpper() + $Env.Substring(1)
    az apic environment create `
      --resource-group $env:RESOURCE_GROUP `
      --service-name $env:APIC_SERVICE `
      --environment-id $Env `
      --title $Title `
      --kind "azure" `
      -o table
}

Write-Host "==> Creating a deployment for v2 pointing at prod (example: an APIM gateway URL)"
az apic api deployment create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-id $env:API_ID `
  --deployment-id "prod-deployment" `
  --title "Production deployment" `
  --environment-id "/environments/$($env:ENV_PROD)" `
  --definition-id "/apis/$($env:API_ID)/versions/v2/definitions/openapi" `
  --server '{"runtimeUri":["https://contoso-apim.azure-api.net/fleet"]}' `
  -o table

Write-Host "==> In the portal: open Fleet Vehicle API > Deployments to show the environment -> runtime URL mapping."
