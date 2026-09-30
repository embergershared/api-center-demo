# Project Context

- **Owner:** Emmanuel
- **Project:** api-center-demo — Azure API Center / APIM / Foundry demo platform for a utility company "Grid Maintenance Agent" narrative
- **Stack:** Bicep (subscription-scope), PowerShell (azd/az CLI orchestration scripts), C# (.NET 10 minimal APIs)
- **Created:** 2026-09-29

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->
- Naming/tagging MUST go through `infra/core/naming.bicep`, `abbreviations.json`, `name-rules.json` per `.github/instructions/naming.instructions.md`.
- New App Service resources (API + MCP hosting) are always deployed, not gated by `DEPLOYMENT_PROFILE`.
📌 Team update (2026-09-29T23:23:13-04:00): Backend locked the shared GridTelemetry.Api contract to GET /substations and GET /substations/{id}/health with camelCase synthetic payloads, which downstream MCP and demo automation now depend on — decided by Backend
📌 Team update (2026-09-29T23:23:13-04:00): DevOps and Docs completed the registration-script and demo-material flow around the new app-hosting outputs, confirming the infrastructure contract is now the basis for API Center and Foundry demos — decided by DevOps, Docs
