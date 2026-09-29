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

Provision the full environment before the meeting, following the README.
API Center requires a supported region such as East US (not East US 2).
Select the environment and load actual provisioned outputs:

```powershell
azd env select apictr-demo
.\scripts\00-vars.ps1
```

Step 1 previews and provisions through azd/Bicep and can take several minutes.
It creates the resource group, API Center, Standard v2 APIM (one capacity unit), monitoring, and
the API Center managed identity's APIM-scoped reader assignment. The full profile
also adds modern Foundry with chat/embeddings deployments, vector-capable
Managed Redis, and authenticated AI gateway policies and telemetry. The deployer
needs `Role Based Access Control Administrator` in addition to `Contributor`.
Step 5 verifies those permissions and configures synchronization without
changing infrastructure. Names include region, subscription code, and azd
environment, for example `apic-use-s3-apictr-demo`.
Continuous synchronization also requires preview `apic-extension` 1.2.0b1 or
later (`az extension add --name apic-extension --upgrade --allow-preview true`).

The intended API Center plan is Standard. Bicep initially creates it with an
explicit Free SKU. After the portal upgrade, set `API_CENTER_SKU` to `Standard`
with `azd env set API_CENTER_SKU Standard` before provisioning again.
After script 05 links the deployed Standard v2 APIM instance, upgrade the API
Center in the portal under **Overview > Manage plan > Standard plan > Submit**
and confirm the plan before the portal walkthrough. API Center Standard is
available at no extra cost while that eligible APIM link remains; a Consumption
APIM instance does not qualify. See the README for the upgrade references.

| # | Script | What to show | Key line |
|---|--------|--------------|----------|
| 1 | `01-create-service.ps1` | Empty API Center service and Standard v2 APIM instance just created | "API Center is our blank system of record; APIM is the gateway we'll connect to it." |
| 2 | `02-metadata-schema.ps1` | Custom metadata fields: lifecycle stage, business owner, compliance tag | "These become searchable/filterable facets — e.g. tag APIs owned by the Fleet Platform team vs. a charging-vendor integration." |
| 3 | `03-register-openapi-api.ps1` | Register **Fleet Vehicle API** (vehicles, battery state, depot charging sessions) from a plain OpenAPI file upload | "Not APIM-only — any spec, any origin, including third-party telematics/charging vendors." |
| 4 | Portal UI | Filter/search catalog by the new metadata fields | "Governance and audit-readiness, not just a list of URLs." |
| 5 | `04-versions-and-deprecation.ps1` | v1 (deprecated) vs v2 (production), then import v2 into APIM at `/fleet` | "Consumers see version history and deprecation status at a glance, while APIM gets the gateway route used by the deployment." |
| 6 | `05-link-apim.ps1` | Link the demo APIM instance for built-in synchronization | "This isn't a one-time import — APIs added or changed in APIM stay synchronized with API Center." |
| 7 | `06-environments-deployments.ps1` | Create dev/test/prod catalog records and map the Fleet Vehicle API to the imported APIM route | "These records describe deployment locations; they do not create separate azd environments or a live Fleet backend." |
| 8 | `07-lint-analysis.ps1` | Run Spectral ruleset against the "messy" **Legacy Depot Charger API** spec | "Shift-left governance — catch bad API design (missing descriptions, no error handling) before a depot charger integration ships." |
| 9 | Portal UI | Self-service developer catalog/portal | "This is what your developers actually browse to find and consume approved APIs — vehicle telemetry, battery, or charging session data — without re-building it." |
| 10 | `08-portal-and-cli-demo.ps1` + VS Code | `az apic` CLI and VS Code extension registering an API from a repo | "Registration becomes part of the dev workflow, not a separate portal chore — useful as more depot/charging integrations come online." |

Script 07's Spectral results are local only. Central API Center analysis requires
separate analyzer configuration; registration alone does not enable it. Expected
lint violations are part of the demonstration, while execution/report failures
stop the script. If Spectral is missing, the script explicitly warns that linting
was skipped.

Script 08 reads the actual portal hostname. For the full profile it checks for
the AI API title and reports when it is not yet visible. Inspect matching
entries' integration source before claiming successful synchronization. It
prints the Foundry project and gateway endpoints but leaves billable calls to
script 09 with explicit confirmation.

## 3. AI governance extension (5-10 min)

Complete the one-time settings in [AI_GATEWAY.md](AI_GATEWAY.md) before the
meeting. Show the modern Foundry project and its two model deployments, then
switch to the APIM `utility-ai` API. Foundry playground calls bypass APIM:
use the gateway endpoint to demonstrate governance.

Run `.\scripts\09-ai-gateway-demo.ps1 -Confirm` with the API-scoped subscription
key entered privately. Explain the synthetic glossary prompt, compare the two
completion IDs, and confirm the semantic-cache lookup in APIM tracing. Do not
equate speed alone with a cache hit. Show token metrics and request counts in
Application Insights using the queries in the AI guide.

Explain that request/token limits protect the backend, while embeddings and
infrastructure still cost money on cache hits. Use the optional lowered token
limit demonstration from the guide if time permits. No live outage prompts,
customer data, or operational advice should be used.

Show the optional `department` metadata field and the `NERC-CIP` compliance-tag
choice in API Center. Emphasize these are inventory classifications, not proof
of compliance. The linked APIM can synchronize the AI API into the catalog.

## 4. Wrap-up (5 min)

Tie back to governance/compliance value:
- Single pane of glass for API inventory across fleet, depot, and energy/charging integrations.
- Audit-ready metadata (owner, lifecycle, compliance tags) out of the box.
- Reduced shadow APIs — anything not in the catalog is a governance gap you can now *see*, important as more charging vendors and depot systems get integrated.
- Easier reuse across teams — discovery before duplication, so vehicle/battery/charging APIs get built once and reused, not re-implemented per depot or business unit.

## Cleanup

```powershell
.\scripts\99-cleanup.ps1
```
Verifies the selected subscription and resource-group ownership, then requires
typing the full group name. Deletes the group and everything in it, including
API Center, Standard v2 APIM, Foundry/project/models, Managed Redis, and monitoring. Legacy CLI-created groups remain
untouched. Deletion completes asynchronously.
