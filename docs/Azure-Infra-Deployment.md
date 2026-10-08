# Azure Infrastructure Deployment

Full demo. Run in PowerShell 7 from the repository root.
APIM and Redis incur charges while idle.

## 1. Check prerequisites

Requires .NET 10 SDK, Contributor + RBAC Administrator (or equivalent).
Subscription display name must end in a hyphen and 1-4 digits, such as `Demo-3`.

```powershell
$PSVersionTable.PSVersion
az version
azd version
az bicep version
dotnet --list-sdks

az extension add --name apic-extension --upgrade --allow-preview true
```

## 2. Sign in

```powershell
az login
azd auth login
```

## 3. Create or reuse the azd environment

Prompts for an environment name, subscription, location, hosting/AI/cache
regions, and publisher details. Press Enter to accept displayed defaults.
Existing environments use saved values as defaults; reruns preserve unchanged
settings and deployed outputs. New-environment defaults: `apic-demo`,
`centralus` for the main/AI/cache regions, `westus3` for app hosting, and publisher
`API Center Demo` / `apicenter-admin@apic-demo.dev`; the subscription default
is embedded in the script and shown at the prompt.
Saves settings in azd, selects the environment/subscription, and clears stale
process overrides. Does not provision resources.

```powershell
.\scripts\setup-environment.ps1
azd env list
```

API Center supports `eastus`, `centralus`, and `eastus2`; preflight checks live
service availability and model quota for the chosen regions, not physical capacity.
For Container Apps capacity errors, change only the app-hosting region in setup.
Region-specific hosting resources are recreated; old resources remain until
separately cleaned up. Keep the main/AI/cache regions unchanged.

## 4. Register resource providers

```powershell
. .\scripts\deployment-context.ps1
$values = Get-DeploymentEnvironment
$subscriptionId = Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID'
$profile = Get-DeploymentValue $values 'DEPLOYMENT_PROFILE'
Assert-DeploymentSubscription $subscriptionId
$catalog = Get-Content .\infra\modules\catalog.json -Raw | ConvertFrom-Json
$providers = $catalog.modules |
    Where-Object { $profile -in $_.profiles } |
    ForEach-Object providers |
    Sort-Object -Unique

foreach ($provider in $providers) {
    az provider register --namespace $provider `
        --subscription $subscriptionId --wait

    if ($LASTEXITCODE -ne 0) {
        throw "Provider registration failed: $provider"
    }
}
```

## 5. Validate and preview

Resolve all errors before continuing.

```powershell
.\scripts\01-create-service.ps1 -PreviewOnly
```

## 6. Provision infrastructure

Review the repeated preview; enter `y` to approve.

```powershell
.\scripts\01-create-service.ps1
```

Only if the postprovision APIM link failed: resolve the reported issue, then retry:

```powershell
.\scripts\05-link-apim.ps1
```

## 7. Deploy and check applications

```powershell
azd deploy

. .\scripts\00-vars.ps1
Invoke-RestMethod "$($env:GRID_API_APP_URL)/substations"
Invoke-RestMethod "$($env:GRID_API_APP_URL)/openapi/v1.json"
```

## 8. Populate the demo catalog

Wait for step 6 to succeed and complete step 7 first; do not run this in parallel
with provisioning. This block reloads azd outputs and stops at the first error.

```powershell
& {
    $ErrorActionPreference = 'Stop'
    . .\scripts\deployment-context.ps1
    $values = Get-DeploymentEnvironment
    $environmentName = Get-DeploymentValue $values 'AZURE_ENV_NAME'
    $subscriptionId = Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID'

    az account set --subscription $subscriptionId
    if ($LASTEXITCODE -ne 0) { throw 'Unable to select the saved subscription.' }

    $json = az deployment sub list --subscription $subscriptionId `
        --query "[].{name:name,state:properties.provisioningState,timestamp:properties.timestamp,tags:tags}" `
        --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Unable to check provisioning status.' }
    $latest = ($json -join [Environment]::NewLine) | ConvertFrom-Json |
        Where-Object { $_.tags.'azd-env-name' -eq $environmentName } |
        Sort-Object timestamp -Descending |
        Select-Object -First 1
    if (-not $latest -or $latest.state -ne 'Succeeded') {
        $state = if ($latest) { $latest.state } else { 'not found' }
        throw "Provisioning for '$environmentName' is $state. Complete steps 6 and 7 before running step 8."
    }

    azd env refresh --environment $environmentName --no-prompt
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to refresh provisioning outputs. Resolve the deployment error before continuing.'
    }
    . .\scripts\00-vars.ps1
    Invoke-RestMethod "$($env:GRID_API_APP_URL)/openapi/v1.json" -TimeoutSec 30 | Out-Null

    .\scripts\02-metadata-schema.ps1
    .\scripts\03-register-openapi-api.ps1
    .\scripts\04-versions-and-deprecation.ps1
    .\scripts\06-environments-deployments.ps1
    .\scripts\07-lint-analysis.ps1
    .\scripts\10-register-grid-telemetry-api.ps1
    .\scripts\11-register-mcp-server.ps1
    .\scripts\08-portal-and-cli-demo.ps1
}
```

Follow script 08's portal/access guidance; synchronization is asynchronous.
For AI/agent setup, see [AI_GATEWAY.md](AI_GATEWAY.md).
