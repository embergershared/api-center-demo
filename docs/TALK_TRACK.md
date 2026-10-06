# Talk Track — Azure API Center Demo (~25–30 min)

## 1. Set the story (2 min)
Problem: as fleets electrify, API sprawl follows — vehicle telemetry, battery
management, depot charging infrastructure, and energy/utility integrations
each spin up their own APIs across teams, vendors, and clouds, with no
central inventory or governance. Position API Center as the **single system
of record** for every API — REST, GraphQL, gRPC, SOAP — regardless of where
it runs: APIM, Functions, AKS, vendor clouds, on-prem depot systems.

> "Electrifying a fleet means a lot more integration surface area — vehicle
> data, battery/charging systems, depot hardware, utility/energy APIs.
> API Center doesn't run any of that traffic — it's the catalog that knows
> about all of it, so nothing gets built twice or governed nowhere."

## 2. Core demo flow (15–20 min)

Before running the numbered scripts, load the shared environment variables:

```powershell
. ./00-vars.ps1
```

| # | Script | What to show | Key line |
|---|--------|--------------|----------|
| 1 | `01-create-services.ps1` | Empty API Center service just created | "This is the blank system of record." |
| 2 | `02-metadata-schema.ps1` | Custom metadata fields: lifecycle stage, business owner, compliance tag | "These become searchable/filterable facets — e.g. tag APIs owned by the Fleet Platform team vs. a charging-vendor integration." |
| 3 | `03-register-openapi-api.ps1` | Register **Fleet Vehicle API** (vehicles, battery state, depot charging sessions) from a plain OpenAPI file upload | "Not APIM-only — any spec, any origin, including third-party telematics/charging vendors." |
| 4 | Portal UI | Filter/search catalog by the new metadata fields | "Governance and audit-readiness, not just a list of URLs." |
| 5 | `04-versions-and-deprecation.ps1` | v1 (deprecated) vs v2 (production) of the Fleet Vehicle API — v2 adds vehicle status and pagination | "Consumers see version history and deprecation status at a glance — critical when a depot integration is still calling v1." |
| 6 | `05-link-apim.ps1` | (If APIM available) built-in sync from an existing APIM instance | "This isn't a one-time import — it stays in sync automatically." |
| 7 | `06-environments-deployments.ps1` | Map Fleet Vehicle API to dev/test/prod with deployment links back to APIM/App Service | "One API, multiple environments, one place to see where it's actually running — dev depot vs. production fleet." |
| 8 | `07-lint-analysis.ps1` | Run Spectral ruleset against the "messy" **Legacy Depot Charger API** spec | "Shift-left governance — catch bad API design (missing descriptions, no error handling) before a depot charger integration ships." |
| 9 | Portal UI | Self-service developer catalog/portal | "This is what your developers actually browse to find and consume approved APIs — vehicle telemetry, battery, or charging session data — without re-building it." |
| 10 | `08-portal-and-cli-demo.ps1` + VS Code | `az apic` CLI and VS Code extension registering an API from a repo | "Registration becomes part of the dev workflow, not a separate portal chore — useful as more depot/charging integrations come online." |

## 3. Wrap-up (5 min)

Tie back to governance/compliance value:
- Single pane of glass for API inventory across fleet, depot, and energy/charging integrations.
- Audit-ready metadata (owner, lifecycle, compliance tags) out of the box.
- Reduced shadow APIs — anything not in the catalog is a governance gap you can now *see*, important as more charging vendors and depot systems get integrated.
- Easier reuse across teams — discovery before duplication, so vehicle/battery/charging APIs get built once and reused, not re-implemented per depot or business unit.

## Cleanup

```powershell
./99-cleanup.ps1
```
Deletes the resource group (and everything in it) created for the demo.
