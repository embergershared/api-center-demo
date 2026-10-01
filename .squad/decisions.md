# Squad Decisions

## Active Decisions

### 2026-09-30: App Service plan reverted to Free F1
**By:** Squad (Coordinator)
**What:** Reverted `infra/modules/app-hosting/main.bicep` back to Free F1 (undoing the same-session Basic B1 change), restoring `alwaysOn: false` on both hosted apps, plus the matching `tests/run-tests.ps1` assertions and `app-hosting` README wording.
**Why:** User asked to switch to Basic B1, then asked to revert to F1 within the same session — reverting to keep the Free-tier cost/quota-safe default.

### 2026-09-30: App Service plan upgraded to Basic B1 (superseded — see revert above)
**By:** Squad (Coordinator)
**What:** Changed `infra/modules/app-hosting/main.bicep` from Free F1 to Basic B1 (`sku.name`/`tier`/`size` = `B1`/`Basic`, `family: 'B'`), and enabled `alwaysOn: true` on both hosted web apps since Basic supports it (Free does not).
**Why:** User asked to switch the App Service plan to Basic B1 for dedicated compute and no cold starts. Updated the matching hard test assertions in `tests/run-tests.ps1` (SKU name/tier and alwaysOn expectation) and the `app-hosting` module README to keep them in sync. Flagged that Basic-tier VM quota is 0 on some sponsored/restricted subscriptions — request a quota increase or fall back to F1 if `azd provision` fails on quota.

### 2026-09-28: Microsoft Learn MCP passthrough module shape
**By:** DevOps
**What:** Added the Microsoft Learn MCP passthrough as its own top-level APIM module (`infra/modules/api-management/mslearn-mcp.bicep`), deployed in both `core` and `full`, and relied on the existing APIM→API Center integration for catalog sync.
**Why:** A separate top-level module avoids the exact-tags-equality test invariant that only targets the main tagged modules, the feature has no Foundry or extra-runtime dependency so it belongs in every profile, and API Center already imports normal APIM APIs asynchronously without a new registration script.

### 2026-09-29: App Service hosting outputs and cross-module wiring
**By:** Lead
**What:** Added an always-on `app-hosting` infra module that deploys one Linux B1 App Service plan plus two Linux Web Apps, and standardized root outputs as `GRID_API_APP_URL`, `GRID_API_APP_NAME`, `GRID_MCP_APP_URL`, and `GRID_MCP_APP_NAME`.
**Why:** Backend, Integration, and DevOps need stable azd output names and a shared hosting contract that works in both `core` and `full` deployment profiles without depending on Foundry/Redis.

- `GridTools.Mcp` receives `GridTelemetryApi__BaseUrl` from the API app's default Azure hostname inside the module.
- Monitoring now exposes `applicationInsightsConnectionString` as a module output for internal wiring only; the root template still does not export any connection-string-like output.
- App names use `globalName(abbreviations.appService, ...)` with deterministic `g***` and `m***` suffixes; the plan uses `azName(abbreviations.appServicePlan, ...)`.

### 2026-09-29: Grid telemetry route contract
**By:** Backend
**What:** `GridTelemetry.Api` exposes `GET /substations` and `GET /substations/{id}/health` as the stable HTTP contract for Integration's MCP server.

- `GET /substations` → `200 OK` with JSON array of objects:
  - `id` (`string`)
  - `name` (`string`)
  - `region` (`string`)
- `GET /substations/{id}/health` → `200 OK` with JSON object:
  - `id` (`string`)
  - `name` (`string`)
  - `region` (`string`)
  - `healthScore` (`number`, integer 0-100)
  - `lastInspected` (`string`, ISO date `yyyy-MM-dd`)
  - `openMaintenanceFlags` (`string[]`)
- Unknown `{id}` → `404 Not Found`

Serialized field names use ASP.NET Core `System.Text.Json` default camelCase exactly: `id`, `name`, `region`, `healthScore`, `lastInspected`, `openMaintenanceFlags`.
**Why:** Integration is building `src/GridTools.Mcp` in parallel and needs an exact, demo-safe REST contract with synthetic-only data and predictable field casing/types.

### 2026-09-29: GridTools MCP config and tool exposure
**By:** Integration
**What:** `src/GridTools.Mcp` reads the downstream API base URL from `GridTelemetryApi:BaseUrl` / `GridTelemetryApi__BaseUrl`, defaults to `http://localhost:5000` when unset, and exposes the `GridTelemetryTools` methods over MCP HTTP using the SDK's default snake_case tool names: `list_substations` and `get_substation_health`.
**Why:** DevOps/Lead need the exact app-setting name for deployed wiring, and Foundry/APIM consumers need the actual MCP tool names the SDK publishes.

### 2026-09-29: Grid hosting registration scripts and Foundry agent wiring
**By:** DevOps
**What:** Added `scripts/10-register-grid-telemetry-api.ps1`, `scripts/11-register-mcp-server.ps1`, `scripts/12-grid-agent-demo.ps1`, and `docs/VSCODE_PUBLISH.md`; also added `GRID_API_APP_URL`, `GRID_API_APP_NAME`, `GRID_MCP_APP_URL`, and `GRID_MCP_APP_NAME` to the `00-vars.ps1` deployment-output export loop.
**Why:** The new always-on App Service apps need repeatable demo wiring into API Center and Foundry without hard-coded hostnames.

- `10-register-grid-telemetry-api.ps1` imports the live OpenAPI document from `"$GRID_API_APP_URL/openapi/v1.json"` into API Center with the same custom metadata schema already used by script 03.
- The live-registration path assumes the deployed `GridTelemetry.Api` still exposes `/openapi/v1.json`; today the app code maps OpenAPI only in `Development`, so production-like App Service settings must preserve that endpoint or script 10 will fail clearly.
- `11-register-mcp-server.ps1` probes `az apic mcp-server --help` and only proceeds if that preview command group exists. In this working environment the blocker is that `apic-extension` is not installed, so the script emits an upgrade/install message for `az extension add --name apic-extension --upgrade --allow-preview true`.
- `12-grid-agent-demo.ps1` uses Foundry REST plus `az rest` instead of a preview SDK surface: it upserts a project connection at `Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview` with `properties.category = "RemoteTool"` and `properties.authType = "None"`, then creates the agent with the MCP attachment at `definition.tools[].project_connection_id` plus `type = "mcp"`, `server_url`, `server_label`, `require_approval`, and `allowed_tools`.
- For the API Center catalog, script 12 deliberately reuses the existing APIM-synchronized `utility-ai` entry instead of inventing a second endpoint record, because that synced gateway URL is the actual governed runtime surface.

### 2026-09-29: Grid Maintenance Agent demo materials updated
**By:** Docs
**What:** Updated `README.md` with the two App Service-hosted grid apps plus scripts 10-12, added a new Grid Maintenance Agent section to `docs/TALK_TRACK.md`, and created `docs/DEMO_SCRIPT.md` as the live operator script. Also captured the work in `.squad/agents/docs/history.md`.
**Why:** The repo now has real GridTelemetry.Api, GridTools.Mcp, and Foundry/API Center wiring, so the documentation needed to shift from aspirational narrative to a seller-ready, runnable demo flow while keeping the synthetic-data and preview-surface caveats explicit.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

## Active Decisions (continued)

### 2026-09-30: APIM MCP endpoints use a dictionary at runtime
**By:** Lead
**What:** Keep `service/apis@2025-09-01-preview`, but emit a `message`-keyed object for `mcpProperties.endpoints` in the Learn MCP passthrough module; apply `any()` only to that property and assert the compiled ARM shape in tests.
**Why:** APIM rejected an array with `Cannot deserialize the current JSON array into Dictionary<string,McpEndpointContract>`, while the published 2025-09-01-preview Bicep/REST docs still incorrectly specify an array. Local compilation cannot prove live service acceptance.
