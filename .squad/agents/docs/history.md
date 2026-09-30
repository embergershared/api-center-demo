# Project Context

- **Owner:** Emmanuel
- **Project:** api-center-demo — Azure API Center / APIM / Foundry demo platform for a utility company "Grid Maintenance Agent" narrative
- **Stack:** Markdown docs (README.md, docs/TALK_TRACK.md, new docs/DEMO_SCRIPT.md)
- **Created:** 2026-09-29

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->
- Existing docs already document the Fleet Vehicle catalog + AI gateway demo (scripts 00-09); new content is additive — a "Grid Maintenance Agent" section plus a dedicated demo script.
- Every doc claim must map to a real, runnable script/command — no aspirational steps.
- 2026-09-29: Documented the live Grid Maintenance Agent flow in README.md, TALK_TRACK.md, and docs/DEMO_SCRIPT.md, including scripts 10-12, App Service-hosted GridTelemetry.Api/GridTools.Mcp, preview caveats for MCP registry and Foundry agent APIs, and the VS Code publish handoff to docs/VSCODE_PUBLISH.md.
📌 Team update (2026-09-29T23:23:13-04:00): Lead, Backend, and Integration locked the hosting/output contract plus live REST and MCP tool surfaces, so demo docs should reference the deployed app URLs, /substations routes, and tool names list_substations/get_substation_health — decided by Lead, Backend, Integration
📌 Team update (2026-09-29T23:23:13-04:00): DevOps completed scripts 10-12 and the VS Code publish handoff, making the end-to-end Grid Maintenance Agent flow runnable rather than aspirational — decided by DevOps
