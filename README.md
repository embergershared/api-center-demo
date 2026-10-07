# Azure API Center Customer Demo Kit

A PowerShell kit for a ~25–30 minute Azure API Center demo, using an
electrified-fleet scenario to show API inventory, metadata, version lifecycle,
APIM synchronization, and developer discovery.

API Center is the catalog, not the API runtime. The included examples are REST
APIs described by OpenAPI files; the scripts do not deploy a working Fleet
Vehicle API backend or import it into API Management.

> **Cost:** script `01` provisions Azure API Center on the **Standard plan** and,
> by default, an API Management (APIM) instance on the **Consumption tier**.
> These are billable resources. Allow time for provisioning before the demo and
> review the cleanup scope below.

## Prerequisites

- PowerShell (`pwsh` recommended) and Azure CLI `>= 2.60`, with `az login`
  completed. These scripts include Windows `az.cmd` JSON-argument workarounds.
- Permissions to create resource groups and provision API Center and APIM in the
  selected subscription, for example `Contributor` at subscription scope.
- For APIM synchronization, permission to assign Azure roles on the APIM
  resource, for example `Role Based Access Control Administrator` at an
  appropriate scope. `Contributor` alone cannot assign roles.
- For portal sign-in setup, permission to create Microsoft Entra app
  registrations and assign Azure roles on API Center. Portal users need the
  **Azure API Center Data Reader** role on the service.
- VS Code with **Azure API Center** (`apidev.azure-api-center`) and, for editor
  linting, **Spectral** (`stoplight.spectral`).
- Optional: Node.js/npm and the Spectral CLI for the local lint demonstration:
  ```powershell
  npm install -g @stoplight/spectral-cli
  ```

Script `01` installs/upgrades `apic-extension`. Script `05` upgrades it with
`--allow-preview true` for the APIM integration commands.

## Layout

```
scripts\   PowerShell scripts 00-08, plus 99-cleanup.ps1
samples\   Fleet Vehicle v1/v2, a deliberately messy legacy API, and .spectral.yaml
docs\      Presenter talk track
```

Only PowerShell scripts are included; there are no Bash equivalents.

## Configure before running

From the repository root, open the shared configuration:

```powershell
code .\scripts\00-vars.ps1
```

Replace the checked-in demo values before running any script:

| Setting | Purpose |
|---------|---------|
| `AZURE_SUBSCRIPTION_ID` | Your target subscription; the script actively selects it with `az account set`. |
| `NAMING_BASE` | Base for `rg-`, `apic-`, and `apim-` resource names; choose names available for your deployment. |
| `LOCATION` | Azure region for provisioning. |
| `RESOURCE_GROUP` | API Center resource group; use a dedicated demo group because cleanup deletes everything in it. |
| `APIM_RESOURCE_GROUP` / `APIM_SERVICE` | APIM instance to create or reuse. Defaults place it in the same resource group as API Center. |

To omit APIM, set `$env:APIM_SERVICE = ""` **in `00-vars.ps1`**. Script `01`
then skips APIM creation, and script `05` skips integration. To reuse APIM, set
its existing service and resource-group names; script `01` skips creation when
it finds that instance.

If creating APIM, also replace `--publisher-email` and `--publisher-name` in
`scripts\01-create-service.ps1`; they currently contain Contoso placeholders.

Each numbered script dot-sources `00-vars.ps1`, which resets its configured
environment variables and selects the subscription. Editing only your shell's
environment variables will not override those assignments. The commented
deployment-context code in that file is inactive; no deployment-output loader
is required.

## Run the demo

Run these commands **from the repository root**, keeping the same PowerShell
session for the later copy/paste examples:

```powershell
az login
. .\scripts\00-vars.ps1

# Run one at a time and inspect the result before proceeding.
.\scripts\01-create-service.ps1
.\scripts\02-metadata-schema.ps1
.\scripts\03-register-openapi-api.ps1
.\scripts\04-versions-and-deprecation.ps1
.\scripts\05-link-apim.ps1
.\scripts\06-environments-deployments.ps1
.\scripts\07-lint-analysis.ps1
.\scripts\08-portal-and-cli-demo.ps1
```

| Script | What it does |
|--------|--------------|
| `00-vars.ps1` | Loads resource names and logical API/environment IDs, then selects the subscription. |
| `01-create-service.ps1` | Creates the configured resource group(s), creates API Center, patches its plan to Standard and verifies it, then creates or reuses APIM. |
| `02-metadata-schema.ps1` | Adds titled metadata fields: lifecycle stage, business owner, and compliance tags. All are optional to support CLI/VS Code registration. |
| `03-register-openapi-api.ps1` | Registers `fleet-vehicle-api` with custom metadata and imports v1, already marked deprecated. |
| `04-versions-and-deprecation.ps1` | Adds production v2 and reaffirms v1's deprecated lifecycle. |
| `05-link-apim.ps1` | Enables API Center's managed identity, grants it API Management Service Reader Role, and creates APIM-to-API-Center synchronization. Retries integration up to six times with 20-second waits. |
| `06-environments-deployments.ps1` | Creates dev/test/prod catalog environments and one production deployment record linked to the v2 definition. |
| `07-lint-analysis.ps1` | Registers the messy Legacy Depot Charger API and runs local Spectral linting if the CLI is installed. |
| `08-portal-and-cli-demo.ps1` | Pauses for manual portal configuration, prints VS Code/CLI registration guidance, and queries production-tagged APIs. |

Scripts announce their operations and display CLI results; they do not echo
every command. Reruns reuse fixed IDs and can update existing catalog content;
the kit is not a transactional or fully idempotent deployment system.

### APIM synchronization and deployment records

Synchronization flows **from APIM into API Center**, not the other way around.
The kit does not populate APIM with the Fleet Vehicle API. Add/import an API in
APIM separately if you want to demonstrate it appearing through synchronization.

Script `06` uses `https://contoso-apim.azure-api.net/fleet` as an illustrative
runtime URL. Replace it in the script if you want the deployment record to
reference a real endpoint. Creating that record does not provision or validate
an API runtime.

### Linting

Script `07` uses `samples\.spectral.yaml`, which extends `spectral:oas` with
demo rules. The legacy sample intentionally produces lint findings; a nonzero
Spectral exit code can be expected for that sample. If Spectral is missing, the
script prints installation instructions and skips local linting.

The script imports the sample but **does not configure a hosted API Center
analyzer or upload the custom ruleset**. Configure service-side analysis
separately if you want to demonstrate centrally generated results.

### Portal and developer registration

Script `08` prompts you to configure portal sign-in manually in the Azure portal:
open the API Center resource, go to **Consumption > Portal settings > Access**,
use **Configure Entra ID > Quick setup**, then **Save + publish**. Press Enter
in PowerShell after setup. Use the published URL from Portal settings rather
than relying on the illustrative hostname printed by the script.

For the VS Code walkthrough, use **Azure API Center: Register API > Step-by-step**
and the distinct title **Fleet Vehicle API (VS Code)**. Reusing the original
catalog API's title can overwrite its custom metadata. Set lifecycle stage and
business owner on the new API in the portal afterward.

Script `08` only prints the CLI registration command; run it yourself from the
repository root:

```powershell
az apic api register `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIC_SERVICE `
  --api-location ".\samples\fleet-vehicle-v2.json"
```

The v2 specification has the title **Fleet Vehicle API (az apic)** so this
auto-detected registration is separate from the main demo API. If working from
the `scripts` directory instead, use `..\samples\fleet-vehicle-v2.json`.

## Cleanup

From the repository root:

```powershell
.\scripts\99-cleanup.ps1
```

The script reloads the configured subscription/resource group, asks for `y`/`Y`
confirmation, and deletes **all resources in `RESOURCE_GROUP`**, including APIM
if it is in that group. It polls every 10 seconds for up to one hour and reports
success, failure, timeout, or an unknown status. A timeout stops polling, not
the Azure deletion operation.

An APIM instance in a separate `APIM_RESOURCE_GROUP` is not deleted. Entra app
registrations created during portal setup are also outside this script's cleanup
scope; review those separately.

See [the talk track](docs/TALK_TRACK.md) for the presenter narrative.


## References

[Azure API Center documentation](https://learn.microsoft.com/en-us/azure/api-center/)

[Azure API Center videos playlist](https://youtu.be/Dvar8Dg25s0?si=nCBCx0WqxQm2Qx60)
