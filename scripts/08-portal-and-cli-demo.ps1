# 08-portal-and-cli-demo.ps1 — helper commands for the self-service portal,
# VS Code extension, and CLI-driven registration moments of the demo.
# This script is mostly informational — it prints the URLs/commands to run live
# rather than fully automating a UI-driven walkthrough.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")

$ApicId = az apic show --resource-group $env:RESOURCE_GROUP --name $env:APIC_SERVICE --query id -o tsv
if ($LASTEXITCODE -ne 0) { throw "Failed to get API Center service '$($env:APIC_SERVICE)'." }

Write-Host "==> 0) Configure the API Center portal sign-in (one-time, in the Azure portal)"
Write-Host "    Open: https://portal.azure.com/#resource$ApicId"
Write-Host "    - Go to Consumption > Portal settings > Access tab."
Write-Host "    - Click 'Configure Entra ID', keep the 'Quick setup' tab, then click 'Configure'."
Write-Host "      (Registers the '$($env:APIC_SERVICE)-apic-aad' Entra ID app, its permissions and redirect URL,"
Write-Host "       and assigns you the 'Azure API Center Data Reader' role.)"
Write-Host "    - Click 'Save + publish'."
Write-Host "    Requires rights to create Entra ID app registrations and to assign Azure roles."
Write-Host "    Other demo users also need the 'Azure API Center Data Reader' role on the service."
Read-Host "    Press Enter once the portal is configured and published"

Write-Host ""
Write-Host "==> 1) Self-service developer portal"
Write-Host "    Portal URL pattern: https://$($env:APIC_SERVICE).portal.<region>.azure-api.net"
Write-Host "    (Confirm exact URL with: az apic show -g $($env:RESOURCE_GROUP) -n $($env:APIC_SERVICE))"
az apic show `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:APIC_SERVICE `
  --query "{name:name, id:id}" `
  -o table
if ($LASTEXITCODE -ne 0) { throw "Failed to show API Center service '$($env:APIC_SERVICE)'." }

Write-Host ""
Write-Host "==> 2) VS Code extension moment"
Write-Host "    - Install 'Azure API Center' extension from the marketplace."
Write-Host "    - Open a repo containing samples/fleet-vehicle-v2.json."
Write-Host "    - Right-click the file > 'Register API in Azure API Center'."
Write-Host "    - Pick service: $($env:APIC_SERVICE), API: create new, fill title/type."
Write-Host "    - Resonates with devs: registration becomes a repo/PR-driven action, not a portal chore."

Write-Host ""
Write-Host "==> 3) az apic CLI — registering an API straight from a repo (scriptable, CI/CD-friendly)"
Write-Host "    Example command to run live:"
Write-Host @'
    az apic api register `
      --resource-group $env:RESOURCE_GROUP `
      --service-name $env:APIC_SERVICE `
      --api-location "./samples/fleet-vehicle-v2.json"
'@
Write-Host "    (az apic api register auto-detects title/version/type from the spec — one command, no portal clicks.)"

Write-Host ""
Write-Host "==> 4) Quick catalog query examples for the 'governance' beat"
Write-Host "List all APIs tagged production:"
az apic api list `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --query "[?customProperties.lifecycleStage=='production'].{title:title, id:name}" `
  -o table
