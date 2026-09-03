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

Before running the numbered scripts, load the shared environment variables. The
base value must be 3–4 alphanumeric characters, such as your initials. It forms
deterministic names such as `apic-jrf-eus01` and `apim-jrf-eus01`:

```powershell
. ./00-vars.ps1 `
	-BaseValue "jrf" `
	-PublisherEmail "api-team@contoso.com" `
	-PublisherName "Contoso"
```

Step 1 provisions a cost-effective Consumption-tier APIM instance and can take
several minutes the first time. Later runs reuse the same instance. Step 5
grants the API Center managed identity read-only access to APIM, so the signed-in
user needs `Role Based Access Control Administrator` in addition to `Contributor`.
Continuous synchronization also requires preview `apic-extension` 1.2.0b1 or
later (`az extension add --name apic-extension --upgrade --allow-preview true`).

| # | Script | What to show | Key line |
|---|--------|--------------|----------|
| 1 | `01-create-service.ps1` | Empty API Center service and Consumption-tier APIM instance just created | "API Center is our blank system of record; APIM is the gateway we'll connect to it." |
| 2 | `02-metadata-schema.ps1` | Custom metadata fields: lifecycle stage, business owner, compliance tag | "These become searchable/filterable facets — e.g. tag APIs owned by the Fleet Platform team vs. a charging-vendor integration." |
| 3 | `03-register-openapi-api.ps1` | Register **Fleet Vehicle API** (vehicles, battery state, depot charging sessions) from a plain OpenAPI file upload | "Not APIM-only — any spec, any origin, including third-party telematics/charging vendors." |
| 4 | Portal UI | Filter/search catalog by the new metadata fields | "Governance and audit-readiness, not just a list of URLs." |
| 5 | `04-versions-and-deprecation.ps1` | v1 (deprecated) vs v2 (production), then import v2 into APIM at `/fleet` | "Consumers see version history and deprecation status at a glance, while APIM gets the gateway route used by the deployment." |
| 6 | `05-link-apim.ps1` | Link the demo APIM instance for built-in synchronization | "This isn't a one-time import — APIs added or changed in APIM stay synchronized with API Center." |
| 7 | `06-environments-deployments.ps1` | Create dev/test/prod environments and map the Fleet Vehicle API production deployment to APIM | "One API, multiple environments, one place to see where the production version is actually running." |
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
Deletes the resource group and everything in it, including API Center and the
Consumption-tier APIM instance created for the demo.
