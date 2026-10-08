# 08-portal-and-cli-demo.ps1 — helper commands for the self-service portal,
# VS Code extension, and CLI-driven registration moments of the demo.
# This script is mostly informational — it prints the URLs/commands to run live
# rather than fully automating a UI-driven walkthrough.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "00-vars.ps1")
. (Join-Path $PSScriptRoot 'demo-cli.ps1')
$specificationPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'samples' 'fleet-vehicle-v2.json'
$profile = Get-DeploymentValue $deploymentValues 'AZURE_DEPLOYMENT_PROFILE'
if ($profile -cnotin @('core', 'full')) { throw 'Unknown deployed profile. Run azd env refresh after successful provisioning.' }

Write-Host "==> 1) Self-service developer portal"
$portalHostname = Invoke-DemoAz -Arguments @(
    'resource', 'show',
    '--ids', $env:APIC_RESOURCE_ID,
    '--api-version', '2024-06-01-preview',
    '--query', 'properties.portalHostname',
    '--output', 'tsv'
) -FailureMessage "Failed to retrieve API Center service '$($env:APIC_SERVICE)'"
if ([string]::IsNullOrWhiteSpace($portalHostname)) {
    Write-Warning 'Azure has not returned a portal hostname. Configure and publish the portal before the walkthrough.'
}
elseif ([uri]::CheckHostName($portalHostname) -ne [UriHostNameType]::Dns) {
    throw 'Azure returned an invalid API Center portal hostname; no portal URL was generated.'
}
else {
    Write-Host "    Portal URL: https://$portalHostname"
}
Write-Host "    Configure and publish access under API Center > Consumption > Portal settings."

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
$registerCommand = @'
    az apic api register `
      --resource-group $env:RESOURCE_GROUP `
      --service-name $env:APIC_SERVICE `
      --api-location '__SPECIFICATION_PATH__'
'@
Write-Host ($registerCommand.Replace('__SPECIFICATION_PATH__', $specificationPath.Replace("'", "''")))
Write-Host "    (az apic api register auto-detects title/version/type from the spec — one command, no portal clicks.)"

Write-Host ""
Write-Host "==> 4) Quick catalog query examples for the 'governance' beat"
Write-Host "List all APIs tagged production:"
Invoke-DemoAz -Arguments @(
    'apic', 'api', 'list',
    '--resource-group', $env:RESOURCE_GROUP,
    '--service-name', $env:APIC_SERVICE,
    '--query', "[?customProperties.lifecycleStage=='production'].{title:title, id:name}",
    '-o', 'table'
) -FailureMessage "Failed to query APIs in API Center service '$($env:APIC_SERVICE)'"

if ($profile -eq 'full') {
    Write-Host ''
    Write-Host '==> 5) Full-profile AI catalog and gateway walkthrough'
    $catalogJson = Invoke-DemoAz -Arguments @(
        'apic', 'api', 'list',
        '--resource-group', $env:RESOURCE_GROUP,
        '--service-name', $env:APIC_SERVICE,
        '--query', "[?title=='Utility AI demonstration'].{name:name,title:title}",
        '--output', 'json'
    ) -FailureMessage 'Failed to check for the AI API in the catalog'
    $catalogEntries = ($catalogJson -join [Environment]::NewLine) | ConvertFrom-Json -NoEnumerate
    if ($catalogEntries -isnot [array]) { throw 'API Center did not return a catalog array.' }
    if ($catalogEntries.Count -eq 0) {
        Write-Warning 'AI API not yet visible in the catalog. Run script 05 to check the APIM integration and allow time for asynchronous synchronization; run this script again later.'
    }
    else {
        $catalogEntries | Format-Table name, title | Out-Host
        Write-Host '    Matching entries found. Inspect their source in API Center to confirm they belong to the APIM integration reported by script 05.'
    }
    Write-Host "    Foundry project endpoint: $(Get-DeploymentValue $deploymentValues 'AZURE_AI_PROJECT_ENDPOINT')"
    Write-Host "    AI gateway endpoint: $(Get-DeploymentValue $deploymentValues 'AI_GATEWAY_URL')"
    Write-Host '    Foundry playground calls bypass APIM. Use script 09 with -Confirm for the billable gateway demo.'
    Write-Host '    See docs\AI_GATEWAY.md for operator access, telemetry settings, and cache tracing.'
}
