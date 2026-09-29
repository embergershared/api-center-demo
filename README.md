# Azure API Center and Utility AI Demo

A fresh, public-endpoint demo platform for API discovery, governance, and AI
cost/usage controls. It combines the existing fleet API catalog walkthrough
with a working APIM AI gateway. No real outage data or operational decisions
belong in this demo.

## Platform

| Layer | Resource | Default configuration |
|---|---|---|
| Catalog | Azure API Center | Standard after the explicit portal upgrade below |
| Gateway | API Management | Standard v2, one capacity unit, system-assigned identity |
| AI execution | Microsoft Foundry | Modern AIServices S0 account and project; Entra authentication |
| Chat model | Foundry OpenAI deployment `chat` | gpt-5.6-luna 2026-07-09, GlobalStandard, capacity 10 |
| Embeddings | Foundry OpenAI deployment `embeddings` | text-embedding-3-small v1, Standard, capacity 10 |
| Semantic cache | Azure Managed Redis | Balanced B0, RediSearch, TLS, non-HA demo configuration |
| Observability | Log Analytics + Application Insights | Pay-as-you-go, workspace-based, identity-authenticated gateway logging |

`DEPLOYMENT_PROFILE=full` is the default. `core` retains just API Center, APIM,
and monitoring resources, without the AI gateway configuration. The full
profile uses public endpoints **with authentication**, not anonymous access.
It does not provision VNets, private endpoints, a classic AI Hub, Storage, or
Key Vault. Modern Foundry hosts the OpenAI models directly.

Managed Redis with RediSearch is required for semantic caching; Basic C0/C1
Azure Cache for Redis cannot replace it. APIM and Redis incur ongoing charges
even while idle. Models, embeddings, telemetry, and retained data can incur
usage charges. Non-HA Redis is for demos only and has no availability SLA.
GlobalStandard can process inference globally; do not imply regional-only
processing or a NERC-CIP compliance certification.

## Prerequisites

- PowerShell 7, Azure CLI >= 2.60, Azure Developer CLI (`azd`), and Bicep CLI.
- Preview `apic-extension` >= 1.2.0b1:
  `az extension add --name apic-extension --upgrade --allow-preview true`.
- `az login` and `azd auth login`, with the same intended subscription.
- Contributor and Role Based Access Control Administrator at subscription
  scope, or equivalent scoped deployment/role-assignment permissions.
- A subscription display name ending in a hyphen and 1-4 digits (for example
  `-3`), used by the existing naming convention.
- Register the required providers before provisioning: `Microsoft.ApiCenter`,
  `Microsoft.ApiManagement`, `Microsoft.CognitiveServices`, `Microsoft.Cache`,
  `Microsoft.Insights`, `Microsoft.OperationalInsights`, and
  `Microsoft.Authorization`. Preflight reports missing registrations.
- Model access/quota and regional availability for the selected models and
  SKUs. Preflight checks the live model catalog and quota; it cannot reserve
  capacity or guarantee a deployment time.

## Azure API Center deployment regions

Azure API Center is available in these Azure public-cloud regions, confirmed
against the resource provider and [Microsoft's available-regions list](https://learn.microsoft.com/azure/api-center/overview#available-regions)
on **2026-09-28**:

| Region | `AZURE_LOCATION` value |
|---|---|
| Australia East | `australiaeast` |
| Canada Central | `canadacentral` |
| Central India | `centralindia` |
| East US | `eastus` |
| France Central | `francecentral` |
| Sweden Central | `swedencentral` |
| UK South | `uksouth` |
| West Europe | `westeurope` |

This demo defaults to **East US**. **East US 2 (`eastus2`) is not supported by
API Center.** This list covers API Center only; the full demo also requires
regional availability for APIM Standard v2, Foundry models, Managed Redis, and
monitoring. Preflight checks those services separately. `AI_LOCATION` and
`CACHE_LOCATION` can differ from `AZURE_LOCATION`.

To refresh the API Center region list for your active Azure subscription:

```powershell
az provider show --namespace Microsoft.ApiCenter --query "resourceTypes[?resourceType=='services'].locations | [0]" --output json
```

## Fresh setup

Run from the repository root. Use a **new local azd environment** after deleting
old Azure resources so stale outputs are not mistaken for live services.
Deleting Azure resources does not delete local azd environments.

```powershell
$subscriptionId = '<subscription-guid>'
$env:AZURE_ENV_NAME = 'utility-ai-demo'
az account set --subscription $subscriptionId
azd env new $env:AZURE_ENV_NAME --subscription $subscriptionId --location eastus --no-prompt
azd env set AZURE_SUBSCRIPTION_ID $subscriptionId
azd env set AZURE_LOCATION eastus
azd env set DEPLOYMENT_PROFILE full
azd env set APIM_PUBLISHER_NAME Contoso
azd env set APIM_PUBLISHER_EMAIL api-team@contoso.com
.\scripts\set-deployment-tags.ps1
.\scripts\01-create-service.ps1 -PreviewOnly
.\scripts\01-create-service.ps1
```

The final command repeats preflight/preview and asks before provisioning.
Review the preview for costs and unexpected changes. These commands have **not**
been executed for you. East US is the default; other API Center locations are
listed [above](#azure-api-center-deployment-regions). AI and cache regions can
be overridden separately; see [AI gateway setup](docs/AI_GATEWAY.md).

`01-create-service.ps1` runs `set-deployment-tags.ps1` before preflight and
preview. It fills missing or blank settings, persists them in the active azd
environment, and prints each initialized value and its source. Existing nonblank
settings are preserved; repeat runs only refresh the last-updated timestamp.

| Missing setting | Default or source |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | Active Azure CLI subscription; first select the intended account with `az account set` |
| `AZURE_LOCATION` | `eastus` |
| `DEPLOYMENT_PROFILE` | `full`; set `core` explicitly for the smaller platform |
| `AI_LOCATION`, `CACHE_LOCATION` | Effective `AZURE_LOCATION` |
| `APIM_PUBLISHER_NAME`, `APIM_PUBLISHER_EMAIL` | `API Center Demo`, `api-team@example.com` (demo placeholder; replace to receive service notifications) |
| Model names, versions, SKUs, capacities, Redis and token settings | Defaults in `infra\main.parameters.json`, matching the platform table |
| Subscription code, repository and timestamps | Subscription display name, Git remote and current Eastern time; existing creation time is retained |

An environment created with only `azd env new <name>` can therefore be prepared
by `.\scripts\01-create-service.ps1 -PreviewOnly` after Azure login and account
selection. Optional owner/cost-center tags may remain empty. Login, permissions,
provider registration, supported regions/models, quota, invalid explicit values,
and missing post-provisioning outputs are not fabricated or bypassed by defaults.

The process `AZURE_ENV_NAME` takes precedence over the project's selected azd
environment. Scripts report the selection source. Keep it consistent with
`azd env select` when switching demos. When using azd directly, run
`set-deployment-tags.ps1` and `preflight.ps1` first: required parameters are
resolved before the preprovision hook, and preview may not run that hook.

Demo scripts reload outputs from the selected environment on each run without
setting a process-level `AZURE_ENV_NAME`. An intentional process override still
takes precedence over `azd env select`. If an older script left a stale override,
clear it with `Remove-Item Env:\AZURE_ENV_NAME -ErrorAction SilentlyContinue`
before selecting another environment. Cleanup verifies the environment name
from the loaded outputs rather than relying on a process override.

Names retain the existing region/subscription/environment contract and stable
uniqueness suffixes. Tags retain repository, azd environment, profile, ownership,
and creation/update timestamps. No credentials are exported as azd outputs.

## Catalog and Standard plan setup

```powershell
.\scripts\00-vars.ps1
.\scripts\02-metadata-schema.ps1
.\scripts\03-register-openapi-api.ps1
.\scripts\04-versions-and-deprecation.ps1
.\scripts\05-link-apim.ps1
```

**API Center is explicitly created on Free (`API_CENTER_SKU=Free`).**
After script 05 links the deployed Standard v2 APIM, open API Center in the
Azure portal: **Overview > Manage plan > Standard plan > Submit**. Confirm
Standard before continuing. The linked eligible APIM provides Standard at no
extra cost while the link remains; deploying the APIM SKU alone does not
activate the benefit. See [Standard upgrade](https://learn.microsoft.com/azure/api-center/frequently-asked-questions#how-do-i-upgrade-my-api-center-from-the-free-plan-to-the-standard-plan)
and [linked-APIM benefit](https://learn.microsoft.com/azure/api-center/overview#standard-plan-benefit-when-api-center-linked-to-api-management).

After upgrading, record the plan for repeat provisioning:

```powershell
azd env set API_CENTER_SKU Standard
```

Azure requires an explicit SKU when updating API Center. Preflight blocks an
accidental Standard-to-Free downgrade; keep this setting aligned with the portal.

```powershell
.\scripts\06-environments-deployments.ps1
.\scripts\07-lint-analysis.ps1
.\scripts\08-portal-and-cli-demo.ps1
```

Custom metadata includes lifecycle, owner, compliance tags including NERC-CIP,
and an optional department. These are classifications, not evidence of
compliance. Synchronization is asynchronous and can take minutes to 24 hours;
the new `utility-ai` gateway API is included through that link. Configure the
API Center portal and access permissions during step 08 as described by the
portal walkthrough. The sample fleet endpoint remains catalog metadata, not a
newly implemented live fleet service.

Script 06's dev/test/prod entries are catalog records within one API Center,
not separate azd environments or provisioned runtimes. Script 07 registers the
messy sample and runs local Spectral when installed; it does not deploy a central
analyzer or upload lint results. It reports expected rule violations separately
from execution/report failures, and warns explicitly when local linting is skipped.

Script 08 retrieves the portal hostname from Azure. In the deployed `full`
profile it also checks for the AI API title in the catalog, reports when it is
not yet visible, and prints the Foundry project and AI gateway endpoints from
azd outputs. Confirm matching entries' integration source in the portal; a title
match alone is not proof of successful synchronization. The walkthrough does
not send AI requests or require AI outputs for a `core` deployment.

## AI demonstration

Follow [AI_GATEWAY.md](docs/AI_GATEWAY.md) for the Foundry playground roles,
Application Insights custom-metric setting, APIM subscription key, cache trace,
token-limit demonstration, and queries. Then run:

```powershell
.\scripts\09-ai-gateway-demo.ps1 -WhatIf
.\scripts\09-ai-gateway-demo.ps1 -Confirm
```

The second command prompts securely for the demo APIM subscription key and
sends two synthetic requests. Keys and response text are not printed.
The gateway restricts this demo to bounded, non-streaming completions. It uses
managed identity to call Foundry and logs metadata/metrics, not prompt bodies.

## Cleanup and development

`.\scripts\99-cleanup.ps1` verifies the subscription and ownership tags, then
requires typing the resource-group name. It deletes **everything in that group**:
API Center, APIM, Foundry/project/models, Redis, and monitoring. Never place
unrelated resources there. Deletion is asynchronous; some services retain
soft-deleted names. Prefer a new environment name rather than purging blindly.
Switching `full` to `core` is not a cleanup operation: incremental deployments
do not delete resources omitted by the new profile.

```powershell
.\scripts\build-catalog.ps1
.\tests\run-tests.ps1
```

The local suite compiles/lints Bicep and checks naming, profiles, resource
security, policies, metadata payloads, and script failures using fake CLIs.
It does not provision resources or make billable model calls. Numbered scripts
use file-based JSON transport where required by Windows `az.cmd`. Preserve
the project's azd hooks when refreshing the starter conventions.

See [TALK_TRACK.md](docs/TALK_TRACK.md) for meeting narration.
