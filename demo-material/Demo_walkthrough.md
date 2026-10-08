# Azure API Center: live demo walkthrough

**Presenter runbook for 8 October 2026 | Environment: `apic-demo-aep`**

**Use the existing deployment. Do not provision, redeploy, delete catalog
assets, or recreate agents immediately before presenting.** This is a
click-first, 15-minute story through three personas. Terminal commands belong
in preparation, not on stage. All grid data is synthetic and demo-safe.

> **The story:** "API Center helps us discover and govern the inventory.
> API Management governs requests that pass through its gateway. MCP makes
> selected capabilities consumable by agents and developer tools."

## Start here: the next 10 minutes

1. Open the links below and sign in to API Center and Foundry **before sharing
   your screen**. Close terminals containing credentials or environment dumps.
2. In the API Center portal, locate **Grid Telemetry API**, **Grid Tools MCP
   Server**, and **Microsoft Learn Docs (MCP passthrough, managed)**.
3. Open the live **A12 health** link. This is the dependable live request:
   a real response from the deployed application, with synthetic data.
4. Open Foundry project `proj-usc-s3-apic-demo-aep`. Check **Build > Agents**
   and **Build > Tools**. Use an existing agent only after a successful tool
   call in its playground. If none is ready, use the configuration-only
   agent scene below; do not troubleshoot agent creation on stage.
5. In VS Code, open `samples\grid-telemetry-v1.json` and the Azure API Center
   extension. **Do not remove the existing Grid Telemetry API.** Use a
   separate publishing example only if the registration flow is rehearsed.
6. Choose the live path now: **Grid request = primary**; **Foundry agent =
   conditional**; **Utility AI request = optional, only if rehearsed**.

### Tabs to open, in presentation order

| Tab | Link / target | Use |
| --- | --- | --- |
| 1 | [API Center developer portal](https://apic-usc-s3-apic-demo-aep.portal.centralus.azure-apicenter.ms) | Discovery, metadata, REST and MCP assets |
| 2 | [Live Grid OpenAPI](https://ca-usw3-s3-apicdemoaep-api.politecoast-92e4d300.westus3.azurecontainerapps.io/openapi/v1.json) | Actual application contract, OpenAPI 3.1.1 |
| 3 | [Live substations](https://ca-usw3-s3-apicdemoaep-api.politecoast-92e4d300.westus3.azurecontainerapps.io/substations) / [A12 health](https://ca-usw3-s3-apicdemoaep-api.politecoast-92e4d300.westus3.azurecontainerapps.io/substations/A12/health) | Dependable live REST demonstration |
| 4 | VS Code: this repository | OpenAPI publishing workflow |
| 5 | [Microsoft Foundry](https://ai.azure.com) > `proj-usc-s3-apic-demo-aep` | Agent tools / rehearsed playground |
| 6 | [API Center administration](https://portal.azure.com/#resource/subscriptions/4c88693f-5cc9-4f30-9d1e-d58d4221cf25/resourceGroups/rg-usc-s3-apic-demo-aep/providers/Microsoft.ApiCenter/services/apic-usc-s3-apic-demo-aep/overview) | Assets, lifecycle, metadata, integration |
| 7 | [API Management](https://portal.azure.com/#resource/subscriptions/4c88693f-5cc9-4f30-9d1e-d58d4221cf25/resourceGroups/rg-usc-s3-apic-demo-aep/providers/Microsoft.ApiManagement/service/apim-usc-s3-apicdemoaep-mdcfz4/overview) | Runtime policies, optional AI Test console |

### Current evidence and boundaries

Checked during preparation on 8 October; browser permissions and UI flows
still require your signed-in rehearsal.

| Asset / capability | Current evidence | What to say |
| --- | --- | --- |
| Grid Telemetry API, ID `grid-telemetry-api` | Registered REST asset; live OpenAPI 3.1.1 and A12 health respond | "This is our deployed application and its registered contract." |
| Grid Tools MCP Server, ID `grid-tools-mcp` | Registered MCP asset with production `/mcp` deployment; initialization, both tool names, and A12 backend tool call succeeded earlier in this session | "The MCP server exposes bounded tools backed by the Grid API." |
| API Center/APIM link, `apim-integration` | Live state readback: `syncing` | "The synchronization link is active; individual catalog updates are asynchronous." |
| Fleet Vehicle API, ID `fleet-vehicle-api` | v1-0 deprecated; v2-0 production | Show lifecycle. **Do not invoke Fleet: it is specification-only.** |
| Managed Learn MCP / Utility AI / Fleet entries | Present, separately from imported copies | Managed entries have stable IDs and runtime mappings independent of sync. |
| Foundry agents | Latest project agent-list readback returned no named agents | Do not promise an existing agent. Check the UI; otherwise show tool configuration only. |
| Private tool catalog, portal Try, Foundry AI Gateway association | Not verified by the deployment or the checks above | Demonstrate only after rehearsal; do not infer readiness from resource existence. |

**Important correction:** `azure.yaml` runs `provision-catalog.ps1` **and**
`05-link-apim.ps1` after provisioning. It creates independent catalog entries
and establishes/verifies the APIM link. There is no need to link again on stage.

## Timing and cut line

| Scene | Persona | 15-minute path |
| --- | --- | --- |
| 0. Set the context | All | 1 min |
| 1. Discover and try the live Grid API | API / MCP developer | 4 min |
| 2. Publish from VS Code | API developer | 2 min |
| 3. Make a tool available to an agent | Foundry agent developer | 3 min |
| 4. Govern inventory and runtime | API administrator | 4 min |
| 5. Close | All | 1 min |

**If you have only 10 minutes:** opening 30 s; discovery/live Grid 3 min;
VS Code 1 min (show the flow, no new registration); agent tools 2 min;
governance 3 min; close 30 s. Skip the optional AI request and central-analysis
discussion. Spend no more than 20 seconds recovering any failing UI step.

---

## 0. Opening (1 minute)

> "We have APIs, MCP servers, and teams building agents. The challenge is not
> just deploying them: it is helping people find the right capability,
> understand its contract, and know who owns it. I'll show that through a
> developer, an agent builder, and an administrator."

Point out the distinction once: **catalog != gateway != application runtime**.

## 1. Developer: discover and try the live Grid API (4 minutes)

**Tab 1: API Center developer portal.**

1. Search for **Grid Telemetry API**. Open ID `grid-telemetry-api`, not a
   separately published sample. Show the description, owner, version, and
   OpenAPI definition with `GetSubstations` and `GetSubstationHealth`.
   > "This contract was imported from the running application, not guessed
   > from a document. Teams can inspect it before writing a client."
2. Show custom metadata: `lifecycleStage: production`,
   `businessOwner: Grid Operations Team <grid-ops@contoso.com>`,
   and `complianceTag: NERC-CIP`. Use filters if available, then clear them.
   > "Ownership and lifecycle make this inventory useful. NERC-CIP here is
   > a demo classification, not evidence of regulatory compliance."
   The custom lifecycle field and version lifecycle are distinct from the
   asset's built-in lifecycle; do not assume every screen shows production.
3. **Switch to tabs 2/3.** Show the live OpenAPI, then `/substations`, then
   `/substations/A12/health`. Point to ID, region, health score, inspection
   date, and maintenance flags. Do not turn the score into operational advice.
   > "This is a real call to our deployed Container App, returning synthetic
   > and deterministic data. It is not a production grid-monitoring system."
   **Be precise:** this browser request goes directly to the Grid API. It is
   not API Center's Try console and does not pass through APIM.
4. Return to API Center. Open **Grid Tools MCP Server**; show its production
   deployment and `/mcp` runtime URL.
   > "The same backend is exposed through two bounded tools:
   > `list_substations` and `get_substation_health`. An agent can discover
   > a substation and request a summary without receiving arbitrary actions."
5. Contrast with **Microsoft Learn Docs (MCP passthrough, managed)**:
   > "This second MCP endpoint passes through API Management. We can catalog
   > both directly hosted tools and gateway-fronted tools."

**Do not browse to `/mcp` as a health test.** MCP initialization uses POST
and protocol headers; a browser GET does not prove tool availability.

## 2. Developer: publish from VS Code (2 minutes)

**Window: VS Code, `samples\grid-telemetry-v1.json`.**

> "Catalog publishing fits into the developer's editor. Deploying the
> application and registering its contract are separate steps."

1. Show the sample's two operations. Explain that this is a local sample,
   while the existing Grid asset contains the live application's contract.
2. Open **Azure API Center: Register API > Manual** and select
   `apic-usc-s3-apic-demo-aep`.
3. **Only if rehearsed:** register a separate REST asset titled
   **Grid Telemetry API - VS Code demo** (ID `grid-telemetry-api-vscode-demo`
   if the UI permits), using `samples\grid-telemetry-v1.json`. Complete the
   version and definition prompts. Do not select or overwrite the live Grid
   asset or any **(managed)** entry.
4. Refresh the catalog and show the new sample, if created.
   > "We've published a discoverable contract. This action does not deploy
   > a Container App or automatically create a working runtime URL."

**Low-risk fallback:** show the command and registration form, cancel before
saving, and return to the already registered live Grid API. Say "this is the
publishing workflow," not "we just published a new API."

If the sample already exists from rehearsal, use it for explanation rather
than deleting it or improvising a second asset on stage.

## 3. Agent builder: connect to a cataloged MCP server (3 minutes)

**Tab: Foundry > project `proj-usc-s3-apic-demo-aep`.**

> "An agent builder needs a tool endpoint, its capabilities, and the correct
> authentication. The catalog is where we curate that information."

### Preferred live path: only with a rehearsed agent

1. In **Build > Tools**, show the private API Center catalog **only if it is
   visible to your presenter account**. Select **Microsoft Learn Docs
   (MCP passthrough, managed)** and inspect its runtime URL:
   `https://apim-usc-s3-apicdemoaep-mdcfz4.azure-api.net/learn-mcp/mcp`.
2. Show **No authentication** for this public, read-only Learn MCP
   passthrough. Do not select Entra or OAuth; this endpoint has no configured
   Entra audience. This is the tool's auth setting, not the presenter's sign-in.
3. Open the already rehearsed `azure-learn-managed` agent if present. Confirm
   its actual model and attached MCP connection. Scripts 12/13 request
   `gpt-chat-latest`; use it only if that deployment exists. Infrastructure
   model deployment and a ready agent are not the same thing.
4. In the playground ask:
   > "Using Microsoft Learn, explain how to register a remote MCP server in
   > Azure API Center. Cite the documentation."
5. Expand the tool activity and show the citation and configured gateway URL.
   > "The tool call uses our APIM-fronted Learn endpoint. That does not, by
   > itself, prove that the agent's model traffic also goes through APIM."

### If no agent is ready: configuration-only path

1. Show the managed Learn MCP asset and runtime URL in API Center.
2. In Foundry, show **Add tool > MCP**, if available, with the endpoint and
   **No authentication**. Inspect or explain the form without saving an
   untested connection.
3. Say:
   > "This is the endpoint and authentication an agent needs. We have not
   > rehearsed a playground run in this project, so I'm showing configuration,
   > not claiming a completed agent integration."

If private-catalog discovery is unavailable, pasting the URL is a **manual
connection workflow**, not proof that the private catalog is integrated.
Do not run scripts 12/13 during the presentation: they replace agent
definitions. A Grid agent can be a future extension; the directly hosted Grid
MCP endpoint does **not** automatically receive APIM's policies.

## 4. Administrator: govern inventory and runtime (4 minutes)

**Tab: Azure portal > API Center `apic-usc-s3-apic-demo-aep`.**

1. **Inventory > Assets (45 s).** Show the deployed Grid REST and MCP assets
   alongside Fleet, Learn, and Utility AI. If you published the VS Code
   sample, identify it explicitly as a separate contract-only example.
   > "API Center brings different origins into one inventory."
2. **Governance > Metadata (45 s).** Show `lifecycleStage`, `businessOwner`,
   `complianceTag`, and `department` if present. Inspect the Grid values
   rather than changing them live.
   > "The administrator defines the vocabulary that developers use to filter
   > and understand the catalog."
   `grid-operational-data` is not an allowed compliance tag. The corrected
   Grid registrations use `NERC-CIP`.
3. **Versions and environments (45 s).** Open **Fleet Vehicle API** with
   ID `fleet-vehicle-api`, not the duplicate numeric-ID synced record or
   `managed-fleet-vehicle`. Show v1 deprecated and v2 production. Show the
   Dev/Test/Prod catalog environments.
   > "Lifecycle and deployment context help consumers choose correctly.
   > These environment records are labels, not three separately deployed
   > Azure environments. Fleet is a specification-only example."
4. **Platforms > Integrations > `apim-integration` (45 s).** Show the actual
   status. Preparation readback was `syncing`.
   > "The deployment hook establishes and verifies this link. APIM changes
   > are synchronized asynchronously. The explicitly managed entries remain
   > independent; matching titles do not make them imported copies."
   If status changes to initializing/error, state that and continue with
   the independent entries. Do not troubleshoot or recreate the link.
5. **Switch to APIM > APIs (1 min).** Show `utility-ai`,
   `mslearn-docs-mcp`, and `fleet-vehicle-api`. Inspect Utility AI inbound
   policies: `llm-token-limit`, `llm-semantic-cache-lookup`, and
   `llm-emit-token-metric`.
   > "API Center governs discovery and inventory. API Management enforces
   > these runtime policies on requests through this API. The direct Grid
   > endpoints we showed earlier do not inherit them."

**Optional, only if time remains:** show **Legacy Depot Charger API** as a
deliberately incomplete contract. Script 07 lints locally when Spectral is
installed; it does not provision a central API Center analysis report.
Only show a portal report that you actually configured and rehearsed.

### Optional Utility AI request (substitute for a scene, do not add time)

Use **APIM > APIs > Utility AI demonstration > Test**, only after a successful
private rehearsal. Select the API-scoped `utility-ai-demo` subscription;
keep **Subscription required** enabled and never expose its key.
Send `POST /chat/completions` with `Content-Type: application/json`:

```json
{
  "messages": [
    { "role": "user", "content": "In one sentence, what does a substation do?" }
  ],
  "stream": false,
  "max_completion_tokens": 128,
  "reasoning_effort": "none"
}
```

> "This request went through the Utility AI gateway."

Show `x-ai-tokens-remaining` if returned. Lower latency on a repeat request
does not prove a cache hit; use authorized APIM tracing if already rehearsed.
Do not claim an API Center browser Try succeeded when using APIM Test instead.
Portal credential access and CORS are separate setup steps.

## 5. Close (1 minute)

> "Developers found a real API and its MCP counterpart. We saw how contracts
> are published from the editor, how an agent gets the information needed to
> connect to a tool, and how administrators manage lifecycle and ownership.
> API Center is the inventory; API Management is the runtime gateway for the
> endpoints routed through it."

If the agent actually ran, mention its tool call and cited answer. Otherwise
say "agent connection workflow," not "working agent integration."

**Next step:** rehearse private-catalog onboarding and add agent/model assets
where useful. Do not promise populated Agents/Models tabs simply because
Foundry resources are deployed.

---

## Fast recovery card

| If this happens | Do this; then move on |
| --- | --- |
| Developer portal sign-in or publication fails | Use API Center **Inventory > Assets** in Azure portal. Identify it as the administrator view. |
| Portal Try is blocked by auth/CORS | Open the live Grid browser links; state this is a direct application call. |
| VS Code registration fails or asset exists | Cancel. Show the form and existing live Grid contract; do not delete or overwrite it. |
| MCP URL gives a browser error | Explain POST-based initialization. Show its deployment URL/tool names; do not diagnose with GET. |
| Foundry catalog or agent is unavailable | Use the configuration-only scene. No on-stage provisioning, role changes, or agent replacement. |
| Learn MCP reports an audience/auth error | Stop the call. Explain this tool needs **No authentication**; repair privately after the demo. |
| Utility AI call fails | Show its contract and policies, then return to the working Grid flow. Do not disable subscriptions. |
| Integration no longer reports `syncing` | Show its actual state; use the independent **(managed)** entries without claiming current sync success. |

## After the demo

- **Keep** `grid-telemetry-api`, `grid-tools-mcp`, all **(managed)** assets,
  the APIM integration, and the deployed applications.
- If you created `grid-telemetry-api-vscode-demo`, remove **only that
  disposable sample** when you no longer need it.
- Keep working Foundry agents/connections as rehearsal backups; do not delete
  them as an automatic reset step.
- No resource-group cleanup or reprovisioning is part of this walkthrough.

## Preparation references (not on stage)

- [Repository setup and registration scripts](../README.md)
- [VS Code publishing mechanics](../docs/VSCODE_PUBLISH.md) -- use the separate
  demo title above to preserve the already registered live Grid asset.
- [AI gateway configuration and request format](../docs/AI_GATEWAY.md)
- Scripts `10-register-grid-telemetry-api.ps1` and `11-register-mcp-server.ps1`
  already succeeded against this environment. They detect placeholder images,
  use schema-compatible metadata, and script 11 uses `az rest`, not an
  unavailable `az apic mcp-server` command.
- [API Center portal setup](https://learn.microsoft.com/azure/api-center/set-up-api-center-portal)
- [Private tool catalog in Foundry](https://learn.microsoft.com/azure/foundry/agents/how-to/private-tool-catalog)
- [Register and discover MCP servers](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server)
