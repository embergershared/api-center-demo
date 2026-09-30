# Project Context

- **Owner:** Emmanuel
- **Project:** api-center-demo — Azure API Center / APIM / Foundry demo platform for a utility company "Grid Maintenance Agent" narrative
- **Stack:** PowerShell (azd/az CLI), Azure App Service, API Center CLI extension (`apic-extension`)
- **Created:** 2026-09-29

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->
- Existing numbered scripts (00-09) follow a strict pattern: `00-vars.ps1` + `demo-cli.ps1` (`Invoke-DemoAz`), secure prompts for keys, `-WhatIf`/`-Confirm` gating for anything billable/mutating.
- New scripts 10-12 continue that numbering: register Grid Telemetry API, register MCP server, create/register the Foundry Grid Maintenance Agent.
📌 Team update (2026-09-29T23:23:13-04:00): Lead established always-on App Service hosting with root outputs GRID_API_APP_URL/NAME and GRID_MCP_APP_URL/NAME; those names are now the deployment contract for registration scripts — decided by Lead
📌 Team update (2026-09-29T23:23:13-04:00): Coordinator fixed GridTelemetry.Api to publish /openapi/v1.json outside Development, removing the production registration blocker noted during script work — decided by Coordinator
- 2026-09-28: Added `infra/modules/api-management/mslearn-mcp.bicep` plus unconditional `infra/main.bicep` wiring so APIM fronts Microsoft Learn's public MCP endpoint at `/learn-mcp` in both `core` and `full` profiles.
- 2026-09-28: Kept the Learn MCP passthrough in a separate top-level APIM child-resource module with no `tags` on backend/API resources to match `ai-gateway.bicep` and stay outside `tests/run-tests.ps1`'s exact tag-equality assertions.
- 2026-09-28: Documented that the new MCP API is cataloged automatically by the existing APIM→API Center integration, so no new API Center registration script was added.
