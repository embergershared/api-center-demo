# Grid Maintenance Agent demo script

Use this as the live operator script for the utility-company conversation.
Everything here assumes the environment was provisioned and the apps were
deployed **before** the meeting. Do not imply that any step uses real
operational data: the Grid Telemetry API and agent behavior are synthetic and
demo-safe by design.

## Pre-demo checklist

Do these before the customer joins:

- Select the correct azd environment and load outputs:

  ```powershell
  azd env select <your-environment>
  .\scripts\00-vars.ps1
  ```

- Confirm the two App Service apps are already deployed via `azd deploy`:
  `grid-telemetry-api` (`src/GridTelemetry.Api`) and `grid-tools-mcp`
  (`src/GridTools.Mcp`).
- Confirm API Center has been upgraded to **Standard** if you plan to run
  `.\scripts\11-register-mcp-server.ps1`.
- If you will demo MCP registration live, make sure the preview Azure CLI
  surface is available:

  ```powershell
  az extension add --name apic-extension --upgrade --allow-preview true
  ```

- Keep [VSCODE_PUBLISH.md](VSCODE_PUBLISH.md) open in a spare tab for the VS
  Code portion.

## 1. Value narrative recap (2 min)

Open with the business framing from the Smart Grid story:

> "The utility is trying to build a Grid Maintenance Agent. That means one team
> needs to discover governed APIs, another team needs to expose grid telemetry
> safely, and the AI team needs to connect tools to a Foundry agent without
> creating shadow endpoints."

Key message:

- **API Center** is the inventory and governance system of record.
- **APIM** is the runtime governance layer for model traffic.
- **Foundry** is where the agent experience lives.
- **GridTelemetry.Api** and **GridTools.Mcp** make the story concrete with
  synthetic data only.

## 2. API Center catalog tour (3-4 min)

Show the existing catalog first so the audience sees the broader platform:

- Open API Center in the Azure portal.
- Show the existing Fleet Vehicle API assets and the synchronized `utility-ai`
  entry from APIM.
- Also call out the synchronized `learn-mcp` entry from APIM as a governance
  example for a public Microsoft-hosted MCP server fronted through the gateway.
- Filter on the custom metadata fields already set up by scripts 02-08:
  lifecycle, owner, compliance tag, and optional department.

Suggested line:

> "This is where enterprise architecture and platform teams get one inventory
> across classic APIs, AI gateway surfaces, and now MCP-connected agent
> dependencies."

## 3. Grid Telemetry API — show it live (3 min)

Open the live API directly from the deployed App Service:

- Browse to `$GRID_API_APP_URL/openapi/v1.json`.
- Point out that the OpenAPI document is live and comes from the deployed
  `GridTelemetry.Api` service.
- Optionally browse to:
  - `$GRID_API_APP_URL/substations`
  - `$GRID_API_APP_URL/substations/<id>/health`

What to say:

> "This is the utility-facing dependency our agent will use. It is a real API,
> but the records are deterministic synthetic substations and health scores. No
> real outage, switching, or field-safety data is exposed in this demo."

If asked what the API returns, call out the real routes:

- `GET /substations`
- `GET /substations/{id}/health`

## 4. MCP server — show the tools (3 min)

Explain that the agent consumes tools, not just raw REST:

- Open `src\GridTools.Mcp\GridTelemetryTools.cs` in the repo, or point to the
  MCP attachment inside `scripts\12-grid-agent-demo.ps1`.
- Call out the two exposed tool names:
  - `list_substations`
  - `get_substation_health`
- Explain that the MCP server is hosted separately as `GridTools.Mcp` and calls
  the deployed REST API using the configured `GridTelemetryApi__BaseUrl`.

Suggested line:

> "MCP gives us a cleaner contract for agent actions. The agent can enumerate
> valid substations and request a health summary, while the backend remains a
> normal governed HTTP API."

## 5. Register both assets in API Center (4-5 min)

Run the registration scripts live:

```powershell
.\scripts\10-register-grid-telemetry-api.ps1
.\scripts\11-register-mcp-server.ps1
```

What each script does:

- **Script 10** imports the live OpenAPI document from
  `$GRID_API_APP_URL/openapi/v1.json` and creates the **Grid Telemetry API**
  entry in API Center.
- **Script 11** registers the remote MCP endpoint at `$GRID_MCP_APP_URL/mcp`
  as **Grid Tools MCP Server** in the API Center MCP registry.

Important caveat to state out loud:

> "`az apic mcp-server` is still a preview/evolving CLI surface as of this
> demo. The script checks for support and fails with an actionable message if
> the preview extension is not available."

After the scripts finish, return to API Center and show the new REST API and
MCP server entries.

## 6. Create the Foundry agent and attach the MCP tool (4-5 min)

Show the agent-creation flow with the real script:

```powershell
.\scripts\12-grid-agent-demo.ps1 -WhatIf
.\scripts\12-grid-agent-demo.ps1 -Confirm
```

Explain what happens:

- The script creates or updates a Foundry project connection of type
  `RemoteTool`.
- That connection points to the deployed MCP endpoint:
  `$GRID_MCP_APP_URL/mcp`.
- The script then creates the **Grid Maintenance Agent** and attaches the MCP
  tool, allowing only `list_substations` and `get_substation_health`.
- It reuses the existing synchronized `utility-ai` API Center entry instead of
  inventing a second governed runtime surface.

Important caveat:

> "This script uses preview/evolving Foundry Agent Service REST APIs through
> `az rest`, so describe it as the current implementation path, not a frozen GA
> contract."

If practical, show the created agent in Foundry after the script completes.

## 7. Tie it back to AI Gateway governance (2-3 min)

Reconnect the grid-agent story to the existing AI governance demo:

- Return to the synchronized `utility-ai` entry in API Center or the APIM
  gateway view.
- Optionally show the synchronized `learn-mcp` asset and explain that it needed
  no extra registration step because the existing APIM integration cataloged it
  automatically.
- Remind the audience that Foundry is where the agent is built, but APIM is
  still the governed path for model traffic.
- Reference `.\scripts\09-ai-gateway-demo.ps1 -Confirm` if you want to replay
  the policy, tracing, and semantic-cache story.

Suggested line:

> "The new part is not that we bypass governance for agents. It's the opposite:
> we catalog the API, catalog the MCP server, build the agent in Foundry, and
> keep runtime AI controls in APIM."

## 8. VS Code publish walkthrough (2 min)

Do not re-teach the whole extension workflow live. Summarize the existing guide
in [VSCODE_PUBLISH.md](VSCODE_PUBLISH.md):

- VS Code can publish `src/GridTelemetry.Api` directly to the Web App named by
  `GRID_API_APP_NAME`.
- After publish, confirm the live OpenAPI URL works before running script 10.
- The Azure API Center VS Code extension can register the Grid Telemetry API
  into API Center from the editor experience.

Suggested line:

> "If the customer asks how a developer would operationalize this without hand
> crafting CLI commands, the repo already includes the VS Code flow."

## 9. Wrap-up talking points (2 min)

Close on these points:

- **Inventory:** REST APIs, AI gateway surfaces, and MCP servers all become
  discoverable assets instead of tribal knowledge.
- **Governance:** API Center plus APIM gives ownership, lifecycle, compliance
  tagging, throttling, and observability.
- **Agent readiness:** Foundry agents can attach tools from governed enterprise
  systems without claiming live operational authority.
- **Demo safety:** The scenario feels utility-specific while staying synthetic,
  deterministic, and safe for customer-facing demos.

## Optional follow-up references

- Story/narrative source: [API Center demo flow.md](API%20Center%20demo%20flow.md)
- Existing broader talk track: [TALK_TRACK.md](TALK_TRACK.md)
- VS Code operator flow: [VSCODE_PUBLISH.md](VSCODE_PUBLISH.md)
