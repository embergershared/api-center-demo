# Azure API Center demo walkthrough (15 minutes)

This is a **live click-only** walkthrough told through three personas. Prepare
and verify the environment before the audience arrives; do not run terminal
commands during the presentation. All utility data is synthetic and demo-safe.
**A successful `azd provision` is not proof that the portal, catalog sync,
backend apps, or Foundry agent experience is ready.**

| Persona | Goal | Where they work |
| --- | --- | --- |
| **API / MCP server developer** | Find, understand, try, and publish APIs and MCP servers | API Center portal, VS Code |
| **Foundry agent developer** | Give an agent a governed tool in minutes | Microsoft Foundry portal |
| **API administrator** | Keep one governed inventory, in sync with the gateway | Azure portal (API Center, API Management) |

## Timeline

| # | Scene | Persona | Time |
| --- | --- | --- | --- |
| 0 | Opening | — | 1 min |
| 1 | Discover in the API Center portal | API / MCP server developer | 4 min |
| 2 | Publish a new API from VS Code | API developer | 2.5 min |
| 3 | Connect an agent to an MCP server | Foundry agent developer | 3 min |
| 4 | Govern the inventory | API administrator | 3.5 min |
| 5 | Wrap-up | — | 1 min |

---

## Before the demo (not shown; allow time for provisioning and access propagation)

### Fresh-environment deployment contract

PowerShell script to start a fresh deployment:

```pwsh
$environment = 'apic-demo-cms-01'
$subscription = '4c88693f-5cc9-4f30-9d1e-d58d4221cf25'

az account set --subscription $subscription
azd env set -e $environment AZURE_SUBSCRIPTION_ID $subscription
azd env set -e $environment AZURE_LOCATION eastus
azd env set -e $environment DEPLOYMENT_PROFILE full
azd env set -e $environment APIM_PUBLISHER_NAME 'API Center Demo'
azd env set -e $environment APIM_PUBLISHER_EMAIL 'cms-api-team@example.com'

$env:AZURE_DEV_USER_AGENT = 'microsoft_foundry_skill'
try {
    azd provision -e $environment --no-prompt
}
finally {
    Remove-Item Env:\AZURE_DEV_USER_AGENT -ErrorAction SilentlyContinue
}
azd deploy
```


From the repository root, select a **new** azd environment. Use
`DEPLOYMENT_PROFILE=full`, an API Center-supported `AZURE_LOCATION` (default
`eastus`), the intended `AZURE_SUBSCRIPTION_ID`, and a real
`APIM_PUBLISHER_EMAIL`. The `azure.yaml` preprovision hooks initialize missing
defaults/tags and check providers, regions, and model quota. Review the preview
before running `azd provision -e <environment> --no-prompt`; then run
`azd deploy -e <environment>` **separately** to publish the two application
images. See [Fresh setup](../README.md#fresh-setup) for the full command
sequence. Use `azd env get-values -e <environment>` to locate resource names
and URLs; do not put secrets in presentation notes.

Fresh defaults: API Center/APIM and monitoring in `eastus`; Foundry and Redis
default to that region; Container Apps/registry default to `westus3`. The
Foundry project receives `chat` (`gpt-5.6-luna`, version `2026-07-09`) and
`embeddings` (`text-embedding-3-small`, version `1`), subject to regional
model availability and quota. Redis defaults to `Balanced_B0` without high
availability. Preflight fails rather than silently substituting another
model/region. A new env needs Azure login and permissions; the new resource
group, assets, and model deployments may incur charges.

| After `azd provision` (full profile) | Important limit |
| --- | --- |
| API Center (`APIC_SERVICE`) on **Standard** by default, with system-assigned identity | Portal sign-in/publishing and the APIM link are separate. Standard may incur charges until linked to an eligible APIM. |
| APIM Standard v2, API Center identity with APIM Reader role | **No API Center/APIM integration is created.** Link later with script 05 only if synchronization is needed. |
| Three independent API Center **(managed)** records: Fleet Vehicle (REST), Learn Docs (MCP), Utility AI (REST), with versions/deployments | These are *not* evidence that APIM sync worked. The separate synced copies have no `(managed)` suffix. |
| APIM `/fleet` OpenAPI sample, `/learn-mcp/mcp` public MCP passthrough, `/ai/chat/completions` Utility AI gateway | Fleet has **no backend**, so don't invoke it. Utility AI requires an API-scoped APIM key. |
| Foundry account/project, `chat` and `embeddings` model deployments; Redis, Application Insights, Log Analytics | **No Foundry AI Gateway association, agent, MCP tool connection, or private-catalog access for presenters is created.** |
| Demo Key Vault containing the generated API-scoped Utility AI subscription key, with API Center secret-reader RBAC | API Center's authorization configuration and presenter credential policy are **not** created. |
| Container Apps environment, registry, identity, Grid Telemetry API and Grid Tools MCP container apps | Apps start on placeholder images until **`azd deploy`** succeeds. Neither app is registered by the postprovision catalog hook. |

The postprovision hook creates only independent API Center entries; it does
not attempt APIM synchronization. A previously created link in a reused
environment is not deleted by provisioning.
The only MCP catalog entry usable without waiting for sync is **Microsoft
Learn Docs (MCP passthrough, managed)**, which has the correct `/learn-mcp/mcp`
runtime URL.

### Finish before the audience arrives

1. **Catalog setup.** After provision, run scripts
   ```pwsh
   .\scripts\02-metadata-schema.ps1
   .\scripts\03-register-openapi-api.ps1
   .\scripts\04-versions-and-deprecation.ps1
   .\scripts\05-link-apim.ps1
   .\scripts\06-environments-deployments.ps1
   ```
   from `scripts\` (in that order) to add
   filterable metadata, a *separate* Fleet Vehicle API with v1 deprecated and
   v2 production, and Dev/Test/Prod catalog environments. Script 04 imports
   the `/fleet` specification into APIM but supplies no live backend; another
   `azd provision` may replace that API with the Bicep-managed specification,
   so recheck it after any reprovision. Script
   Run script 05 **once**, only when you intend to link this environment's
   APIM to API Center; it checks the provisioned identity and APIM Reader
   assignment and starts asynchronous synchronization. If a link already
   exists or is stuck at `Initializing`, inspect and resolve it in API Center
   before rerunning script 05; reprovisioning does not reset it. An
   `Initializing` link is not a successful demo of sync. If it never becomes
   healthy, omit the sync claim and use the independent **(managed)** entries.
   Script `07-lint-analysis.ps1` registers the
   deliberately messy Legacy Depot Charger example and, if Spectral is
   installed, lints it **locally**. It does **not** create or upload an API
   Center analysis report. Do not show a portal lint report unless you have
   configured and verified central analysis separately.
2. **Foundry AI Gateway (separate from API Center's APIM link).** After
   `azd provision`, open [Foundry](https://ai.azure.com) with **New Foundry**
   selected. Under **Manage > AI Gateway > Add AI Gateway**, choose the
   provisioned Foundry **resource** and **Use existing** APIM; select this
   environment's Standard v2 APIM, name the gateway, and select **Add**.
   Wait for its status to read **Enabled**. The operator needs Foundry
   resource management access and API Management Service Contributor (or
   Owner) on the APIM instance, in the same tenant and subscription.
   The project from `azd provision` predates this association: select the
   enabled gateway, find the **Utility AI demo** project and choose
   **Add project to gateway**; confirm **Gateway status: Enabled**. You
   do **not** need to delete and recreate the project. Alternatively, create
   a new project in that Foundry resource *after* the gateway is Enabled;
   new projects inherit the gateway. The existing project's `chat` and
   `embeddings` model deployments remain available on the Foundry resource.
   This Foundry control-plane association is **not** the same as the
   provisioned `/ai` Utility AI APIM policy or API Center's `apim-integration`.
   Confirm an authorized Foundry model request increments APIM **Requests**
   metrics before claiming Foundry traffic traverses the gateway. See
   [Foundry AI Gateway setup](https://learn.microsoft.com/azure/foundry/configuration/enable-ai-api-management-gateway-portal).
3. **Plan and portal.** Confirm API Center is on Standard in **Overview >
   Manage plan**. Only if this environment explicitly selected Free, upgrade
   there after linking APIM and set `API_CENTER_SKU=Standard` in this azd
   environment to preserve the upgrade on later provisions. Standard may
   incur charges until the eligible APIM link is established. Configure
   **Consumption > Portal settings >
   Access > Configure Entra ID > Save + publish**. Do not enable anonymous
   access to expose demo API keys. Sign in as the intended presenter. Follow
   [portal setup](https://learn.microsoft.com/azure/api-center/set-up-api-center-portal)
   for VS Code portal-view redirect URIs if using that view.
4. **Permissions.** Give the presenter **Azure API Center Data Reader** for
   discovery and a suitable Foundry project role for agent creation and tool
   use. API Center registration/editing also needs write permissions. Assign
   roles well in advance: propagation can take up to 24 hours. The Foundry
   project and its models alone do not grant the presenter access to the API
   Center private tool catalog.
5. **Utility AI authorization.** The provisioned key is in the demo vault as
   `utility-ai-subscription-key`; never show or copy it on screen. Under API
   Center **Governance > Authorization**, add an **API Key** configuration:
   **Header** `Ocp-Apim-Subscription-Key`, referencing that secret. On
   **Utility AI demonstration (managed) > Versions > Manage Access**, attach
   the configuration and grant the presenter credential access. Do this on
   the **managed** API version (`v1-0-0`), not an unverified synced copy.
   [Configure API access](https://learn.microsoft.com/azure/api-center/authorize-api-access)
   explains the UI. Keep **Subscription required** enabled in APIM:
   gateway policies use `context.Subscription.Id` and throw HTTP 500 on
   unauthenticated keyless requests. API Center's Try console also requires
   the browser to send `Content-Type: application/json`. The Utility AI APIM
   policy has **no portal-origin CORS policy**; if a browser test is blocked,
   add and rehearse an origin-restricted APIM CORS policy *before* the demo
   (manual policy edits can be overwritten by another `azd provision`).
   Alternatively use APIM's **Test** tab with the API-scoped subscription
   selected; do not claim API Center Try works without a successful rehearsal.
6. **Foundry tool.** In Foundry **Build > Tools**, verify the private API
   Center catalog is visible to the presenter and that **Microsoft Learn Docs
   (MCP passthrough, managed)** resolves to `MSLEARN_MCP_URL`. Connect it and
   create a test agent with the `chat` model *before* the demo if live creation
   has not been rehearsed. If Foundry does not list the catalog, check project
   access and API Center Data Reader; do not claim integration works based
   solely on the Foundry model being deployed. If a direct MCP connection is
   used instead, label it as a **manual URL fallback**, not private-catalog
   integration.
7. **VS Code.** Install the **Azure API Center** extension and sign in to
   the same subscription. Open this repository and
   `samples\grid-telemetry-v1.json`. Follow
   [VS Code registration](../docs/VSCODE_PUBLISH.md#register-it-in-api-center-from-vs-code)
   and rehearse the extension UI. Register the spec as **Grid Telemetry API**,
   *not* the managed Fleet/Utility examples. This is **catalog publishing**,
   not container deployment. If you want to show live Grid Telemetry later,
   `azd deploy` and verify `GRID_API_APP_URL/openapi/v1.json` beforehand.
   Rerun script 02 in existing environments so its custom metadata fields
   are optional for VS Code registration; set lifecycle and owner after
   registration in API Center.

### Go/no-go checks on the new environment

- [ ] Verify `azd provision` **and** its postprovision hook finish without
      error; `azd deploy` finishes if the Grid services are mentioned as live.
- [ ] API Center portal sign-in works and lists the **managed** Utility AI and
      Learn MCP entries. Fleet is **specification only**. Neither Agents nor
      Models is auto-registered in API Center.
- [ ] APIM `utility-ai` still requires a subscription. In **APIM > APIs >
      Utility AI demonstration > Test**, send the JSON shown in scene 1 with
      `Content-Type: application/json` and the API-scoped subscription selected;
      require HTTP 200. A keyless HTTP 500 is *not* a Foundry failure.
- [ ] If using **API Center > Try this API** live, require a real HTTP 200
      from that browser with the attached key; if not, use APIM Test and
      explain the portal authentication/CORS work remaining.
- [ ] Learn MCP `initialize` works via `MSLEARN_MCP_URL`; a GET 405 is not a
      valid health check for this POST-based endpoint. The Fleet `/fleet`
      runtime is intentionally not tested.
- [ ] If script 05 was run, `apim-integration` reports successful
      synchronization *before* making any automatic-sync claim. If it remains
      initializing or errors, show its state honestly and use the
      **independently managed** entries; do not call these synchronized.
- [ ] Foundry **Manage > AI Gateway** and the provisioned project both show
      **Enabled**. Confirm Foundry model traffic in APIM metrics before
      claiming model requests use the Foundry AI Gateway; this is independent
      of API Center's APIM integration.
- [ ] Foundry **Build > Tools** actually displays the managed Learn MCP
      catalog entry; verify an agent tool call before claiming the agent path.
- [ ] **Grid Telemetry API** is absent from the catalog at showtime (remove
      any rehearsal registration). Have VS Code and browser tabs ready.

---

## 0. Opening (1 min)

> "Every team builds APIs, and now MCP servers, agents, and models too. API
> Center is the single inventory where developers find them, agent builders
> plug into them, and administrators govern them. In the next 15 minutes you'll
> see the same catalog through three people's eyes."

---

## 1. API / MCP server developer: discover in the API Center portal (4 min)

**Tab:** API Center portal.

1. **Asset types (30 s).** Point out the tabs or filter for **APIs**, **MCP
   servers**, **Agents**, and **Models**.
   > "One catalog can inventory API and AI assets, not just REST."
2. **Filters (30 s).** Open the filter pane. Filter by **API type** (REST,
   MCP), then by **lifecycle stage**. Then use a custom metadata filter such as
   `businessOwner` or `complianceTag` **if script 02 was completed**. Clear
   the filters.
   > "These filters use the administrator's catalog metadata."
3. **Utility AI demonstration (managed) (1.5 min).** Search for and open the
   **(managed)** API, not an identically named APIM-synchronized copy.
   - **Documentation / Overview.** Point out the description, lifecycle,
     version, and the **API Management (independently managed)** deployment.
   - **API specification > Operations.** Select `POST /chat/completions` and
     show the request and response schema.
   - **Try this API (only if the morning-of browser test returned HTTP 200).**
     Select the configured version, confirm the authentication option, and
     send **with `Content-Type: application/json`**:

     ```json
     {
       "messages": [{ "role": "user", "content": "In one sentence, what does a substation do?" }],
       "stream": false,
       "max_completion_tokens": 128,
       "reasoning_effort": "none"
     }
     ```

     Point out the `x-ai-tokens-remaining` response header if returned.
     > "That response went through the governed AI gateway. Token limits and
     > caching apply to an authenticated request."

     **Otherwise:** show the specification here; switch to **APIM > APIs >
     Utility AI demonstration > Test**, select the demo subscription, set
     `Content-Type: application/json`, and send the same payload. Do not
     describe this as a successful API Center portal test. A 401 means the
     key is missing/invalid, a 400 `text/plain` means the content type is
     wrong, and a 500 after turning off the subscription requirement is a
     policy error; keep authentication enabled.
4. **Microsoft Learn Docs (MCP passthrough, managed) (1 min).** Open the
   **managed** entry, not a synced duplicate.
   - **Documentation to connect.** Show the endpoint URL, the
     **streamable HTTP** transport and that the APIM passthrough requires
     no subscription key.
   - **Install in VS Code** (if offered in the portal): select it, accept
     the editor prompt, and show the server in the VS Code MCP tools list.
     This step needs a prior rehearsal; do not promise an automatic
     connection merely because the catalog entry exists.
     > "The catalog gives developers the governed gateway endpoint and
     > instructions to connect from their editor."
5. **Agents and Models (30 s).** Open the **Agents** tab, then **Models**.
   Both are empty.
   > "The inventory has space for these types, but this deployment doesn't
   > register an agent or model as an API Center asset."

---

## 2. API developer: publish a new API from VS Code (2.5 min)

**Window:** VS Code, with `samples\grid-telemetry-v1.json` open.

> "I've built the Grid Telemetry API, and I want other teams and agents to find
> it. I'll publish it without leaving my editor."

1. Show the static OpenAPI file briefly: two operations,
   `GetSubstations` and `GetSubstationHealth`. It documents the source
   routes; it does not deploy or connect to the Grid API automatically.
2. In VS Code open the Command Palette and choose **Azure API Center:
   Register API** > **Manual**. Select this demo's `APIC_SERVICE`, enter
   **Grid Telemetry API** as a new REST API, and select
   `samples\grid-telemetry-v1.json` as the definition file when prompted.
   Complete the version and definition prompts. Do not select the
   provisioned **Fleet Vehicle API (managed)**. If registration reports
   missing required metadata, stop and rerun script 02 before the demo;
   the extension does not collect custom required fields.
3. Refresh the extension and API Center portal; search for **Grid Telemetry
   API**. Show its OpenAPI definition. This registers catalog metadata
   **only**; it does not publish a Container App or create a deployment URL.
   > "My OpenAPI definition is discoverable without running a registration
   > script on stage."

---

## 3. Foundry agent developer: connect an agent to an MCP server (3 min)

**Tab:** Foundry portal, on project `AZURE_AI_PROJECT_NAME`.

> "I'm building an agent. I don't want to hunt for MCP URLs on wikis. I want
> my company's approved tools."

1. Go to **Build** > **Tools**. Search or filter for the private catalog named
   after `APIC_SERVICE`.
   > "This list *is* API Center. The administrator curates it, and I just
   > consume it."
2. Select **Microsoft Learn Docs (MCP passthrough, managed)** if it is
   actually visible in the private catalog. Show that the endpoint matches
   `MSLEARN_MCP_URL` and does not require an APIM subscription key. Use
   the portal's **Connect/Add** flow (labels vary by portal version) and select
   **No authentication**. Do not select Microsoft Entra or OAuth: Foundry then
   attempts to fetch a token and fails because this public endpoint has no
   Entra audience.
3. Go to **Build** > **Agents** > **Create agent**:
   - Name: `azure-learn-managed`
   - Model: `chat`
   - Instructions: `Answer Azure questions using the Microsoft Learn tool. Cite the docs.`
   - **Tools** > **Add** > select the Learn MCP tool you just connected.
4. In the **Playground**, ask:
   `How do I register an MCP server in Azure API Center?`
   Expand the tool call and verify it used the MCP gateway URL.
   > "Foundry uses the API Center-discovered MCP endpoint. APIM is the
   > gateway for this tool, separate from the agent's model connection."

**Fallback:** If private-catalog discovery fails, use Foundry **Add tool >
MCP** and paste `MSLEARN_MCP_URL` from the managed API Center entry.
Say plainly that this is **manual MCP connection**, not proof of private
tool-catalog integration. Select **No authentication**. If the portal does not
persist that choice or reports `Missing required query parameter 'audience'`,
run `.\scripts\13-learn-agent-demo.ps1 -Confirm` before the presentation. The
script creates the project connection explicitly with `authType: None` and
replaces the `azure-learn-managed` agent with that connection through the
supported `azd ai connection create --auth-type none` path. If the
direct tool call still fails, show its configuration and skip the live agent
response.

---

## 4. API administrator: govern the inventory (3.5 min)

**Tab:** Azure portal, open to the API Center resource.

1. **Inventory (30 s).** Go to **Inventory** > **Assets**. Show the REST APIs,
   the MCP server, and the new **Grid Telemetry API** published two minutes
   ago.
2. **Metadata (45 s).** If script 02 ran, go to **Governance** >
   **Metadata** and show `lifecycleStage`, `businessOwner`,
   `complianceTag`, and `department`. If the account has edit access, open
   **Grid Telemetry API** and set `lifecycleStage` to `production`,
   `businessOwner` to `Grid Operations Team`, and `complianceTag` if desired.
   > "The same fields drive the portal filters the developer used."
3. **API analysis (45 s).** If central analysis was configured and verified
   separately, open its actual report for **Legacy Depot Charger API**.
   Otherwise, show its definition and explain that script 07 can detect
   missing descriptions and operation IDs **locally**; no portal report or
   automatic lint result is provisioned.
   > "Central analysis is an optional governance step, not something this
   > environment provisions by default."
4. **Versions and lifecycle (30 s).** Open **Fleet Vehicle API** > **Versions**.
   Show v1 deprecated and v2 production **only if scripts 03/04 ran**.
   In **Environments**, show Dev, Test, and Prod **only if script 06 ran**;
   these are catalog labels, not additional live Azure deployments.
5. **APIM and catalog (1 min).** If script 05 ran, open **Platforms >
   Integrations > `apim-integration`**. State its *actual* sync status; if it
   is `initializing` or `error`, do **not** claim automatic sync works.
   If the script was skipped, explain that linking is a separate, deliberate
   administrator action.
   Switch to APIM > **APIs**: point out `utility-ai`, `mslearn-docs-mcp`
   and specification-only `fleet-vehicle-api`. In the Utility AI inbound
   policy show `llm-token-limit`, `llm-semantic-cache-lookup`, and
   `llm-emit-token-metric`. Point back to the **(managed)** API Center
   entries, created independently by the azd postprovision hook:
   > "APIM governs runtime requests. API Center inventories our APIs.
   > These stable catalog entries don't depend on the asynchronous APIM
   > synchronization. Once sync is healthy, it adds separate imported copies."

---

## 5. Wrap-up (1 min)

- **Developers** discover cataloged APIs and MCP servers, publish an OpenAPI
  definition from VS Code, and try or install an asset when its authentication,
  browser access, and runtime were verified beforehand.
- **Agent builders** can use the private tool catalog **if discovery and
  access were verified**; otherwise the connection shown was a manual MCP
  endpoint setup, not automatic integration.
- **Administrators** manage metadata, lifecycle and catalog environments;
  central lint reports and healthy APIM synchronization need separate
  verification. APIM enforces runtime policies.
- **Next:** register agents and models so the empty **Agents** and **Models**
  tabs become the organization's AI catalog.

---

## Reset after the demo

- Delete **Grid Telemetry API** from API Center so the next run starts clean.
- Delete the `azure-learn-managed` agent and the tool connection in
  Foundry, unless you keep them as a backup.
- Remove the Learn MCP server from VS Code (`MCP: List Servers` > remove).

## References

- Previous scripted version: [DEMO_SCRIPT.md](DEMO_SCRIPT.md)
- [Set up the API Center portal](https://learn.microsoft.com/azure/api-center/set-up-api-center-portal)
- [Create a private tool catalog in Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/how-to/private-tool-catalog)
- [Register and discover MCP servers in API Center](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server)
