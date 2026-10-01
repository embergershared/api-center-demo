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
| App-hosted REST API | `GridTelemetry.Api` | Container App hosting a demo-safe .NET Minimal API with `/substations`, `/substations/{id}/health`, and live OpenAPI at `/openapi/v1.json` |
| App-hosted MCP server | `GridTools.Mcp` | Container App hosting a remote MCP server at `/mcp`, exposing `list_substations` and `get_substation_health` backed by `GridTelemetry.Api` |
| Governed public docs MCP | Microsoft Learn MCP passthrough | APIM exposes `/learn-mcp` as a governed passthrough to Microsoft's public, read-only Learn MCP server for docs and code-sample search |
| Semantic cache | Azure Managed Redis | Balanced B0, RediSearch, TLS, non-HA demo configuration |
| Observability | Log Analytics + Application Insights | Pay-as-you-go, workspace-based, identity-authenticated gateway logging |

`DEPLOYMENT_PROFILE=full` is the default. `core` retains just API Center, APIM,
and monitoring resources, without the AI gateway configuration. The full
profile's AI runtime uses public endpoints **with authentication**, while the
`/learn-mcp` passthrough remains a public read-only route to Microsoft Learn.
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

App hosting (the `GridTelemetry.Api`/`GridTools.Mcp` Container Apps
environment and container apps) uses its own `APP_HOSTING_LOCATION`,
defaulting to **West US 3**, and a Consumption-only Container Apps
environment, independent of `AZURE_LOCATION`. Some subscriptions have zero
App Service VM quota for the Basic (B1)/PremiumV4 (P0V4) tiers in East US
(and East US 2); West US 3 with Container Apps Consumption was confirmed to
have available quota, avoiding that quota error without moving API
Center/APIM out of a supported region. Override the region with
`azd env set APP_HOSTING_LOCATION <region>` if your subscription's quota
differs.

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

After provisioning, `azd deploy` publishes the two Container Apps-hosted demo
services defined in `azure.yaml`: `grid-telemetry-api` (`src/GridTelemetry.Api`)
and `grid-tools-mcp` (`src/GridTools.Mcp`). That deploy step has **not** been
run for you automatically. Script 10 expects the live Grid Telemetry OpenAPI
document to be reachable at `$GRID_API_APP_URL/openapi/v1.json`. Both .NET
projects explicitly enable SDK container support for `azd deploy`.

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
| `APP_HOSTING_LOCATION` | `westus3` (independent of `AZURE_LOCATION`; see [above](#azure-api-center-deployment-regions)) |
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
and creation/update timestamps. The Bicep deployment also applies
`SecurityControl=Ignore` to the resource group and taggable resources; child
resources that do not support Azure tags cannot carry it. No credentials are
exported as azd outputs.

## Catalog and Standard plan setup

`azd provision` runs `scripts/provision-catalog.ps1` after infrastructure
deployment. It creates independently managed catalog
entries for Fleet Vehicle and Learn MCP; the default `full` profile also
creates Utility AI. REST definitions are imported from the repository.
The Fleet route is a specification-only demo, not a live Fleet backend.

No API Center/APIM integration is created by provisioning. If you choose to
run script 05 after provisioning, synchronized entries may appear separately;
only then are duplicates expected. Use entries with **(managed)**
in the title (Learn uses **MCP passthrough, managed**) for stable runtime URLs.
The managed IDs are `managed-fleet-vehicle`, `managed-mslearn-mcp`, and
`managed-utility-ai`, separate from Azure-generated synchronization IDs.
Previously restored numeric-ID entries are not deleted by provisioning.
The Learn deployment points to `/learn-mcp/mcp`. Reruns reuse the managed IDs
and verify their URLs. Script 05 explicitly creates the APIM integration after
checking the API Center identity and APIM Reader role. Synchronization is
asynchronous: confirm its state in the portal before claiming it works. If an
older environment already has a stuck link, provisioning leaves it untouched;
resolve it before running script 05 again.

The **Foundry AI Gateway association is a different integration**. To route
Foundry project model traffic through the existing APIM instance, in Foundry
(new) select **Manage > AI Gateway > Add AI Gateway**, choose this Foundry
resource and **Use existing** APIM, then wait for **Enabled**. Open that
gateway and select **Add project to gateway** for the project provisioned by
azd; existing projects do not inherit the association automatically. A
project created afterward inherits the enabled gateway. Verify a Foundry
model request increments APIM Requests before claiming the integration works.
See [the walkthrough](demo-script/Demo_walkthrough.md#finish-before-the-audience-arrives)
and [Microsoft's setup instructions](https://learn.microsoft.com/azure/foundry/configuration/enable-ai-api-management-gateway-portal).

```powershell
.\scripts\00-vars.ps1
.\scripts\02-metadata-schema.ps1
.\scripts\03-register-openapi-api.ps1
.\scripts\04-versions-and-deprecation.ps1
# Optional, after provisioning, to start APIM synchronization:
.\scripts\05-link-apim.ps1
```

**API Center defaults to Standard (`API_CENTER_SKU=Standard`).** A fresh
provision creates Standard before script 05 links APIM, so Standard charges
may apply until an eligible APIM link is established. The deployed Standard v2
APIM provides Standard at no extra API Center cost **while linked**; deploying
APIM alone does not activate that benefit. Set `API_CENTER_SKU=Free` explicitly
before provisioning if you prefer the Free plan and its feature limits. See
[Standard upgrade](https://learn.microsoft.com/azure/api-center/frequently-asked-questions#how-do-i-upgrade-my-api-center-from-the-free-plan-to-the-standard-plan)
and [linked-APIM benefit](https://learn.microsoft.com/azure/api-center/overview#standard-plan-benefit-when-api-center-linked-to-api-management).

If an existing environment was explicitly pinned to Free, link APIM with
script 05, upgrade using **Overview > Manage plan > Standard plan > Submit**,
then record the plan for repeat provisioning:

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
the linked APIM instance now contributes both the `utility-ai` API and the
public Microsoft Learn MCP passthrough at `/learn-mcp` through that link with
no extra registration step. Configure the API Center portal and access
permissions during step 08 as described by the portal walkthrough. The sample
fleet endpoint remains catalog metadata, not a newly implemented live fleet
service.

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

## Grid Maintenance Agent extension

Once the Container Apps are deployed, extend the catalog/governance story
with the working Grid Maintenance Agent demo assets:

```powershell
.\scripts\10-register-grid-telemetry-api.ps1
.\scripts\11-register-mcp-server.ps1
.\scripts\12-grid-agent-demo.ps1 -WhatIf
.\scripts\12-grid-agent-demo.ps1 -Confirm
.\scripts\13-learn-agent-demo.ps1 -WhatIf
.\scripts\13-learn-agent-demo.ps1 -Confirm
```

- `10-register-grid-telemetry-api.ps1` downloads the live OpenAPI document from
  `GridTelemetry.Api` and registers **Grid Telemetry API** in API Center using
  the same custom-metadata pattern as script 03.
- `11-register-mcp-server.ps1` registers **Grid Tools MCP Server** in the API
  Center MCP registry and requires API Center **Standard** plus preview
  `apic-extension` support for `az apic mcp-server`. If that command group is
  unavailable, the script stops with an actionable install/upgrade message
  rather than pretending registration succeeded.
- `12-grid-agent-demo.ps1` uses preview/evolving Foundry Agent Service REST
  APIs via `az rest` to create or update the **Grid Maintenance Agent**, attach
  the remote MCP tool connection, and verify that the governed runtime remains
  the existing synchronized `utility-ai` catalog entry instead of a duplicate
  API Center record. The agent uses the `gpt-chat-latest` model deployment.
- `13-learn-agent-demo.ps1` creates or repairs the **azure-learn-managed**
  agent and its Microsoft Learn MCP project connection. The APIM passthrough is
  public and read-only, so the connection is created through the supported
  `azd ai connection create` command with `--auth-type none`. The agent uses
  the `gpt-chat-latest` model deployment.
  Do not configure Microsoft Entra or OAuth authentication for this endpoint:
  those modes trigger token acquisition and require an audience that this
  unauthenticated MCP server neither publishes nor validates.

These assets remain demo-safe by design: `GridTelemetry.Api` serves synthetic,
deterministic substation data only, and the agent instructions explicitly avoid
real outage guidance or operational authority. For a VS Code-based publish flow,
see [VSCODE_PUBLISH.md](docs/VSCODE_PUBLISH.md).

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
