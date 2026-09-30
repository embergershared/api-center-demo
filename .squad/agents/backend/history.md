# Project Context

- **Owner:** Emmanuel
- **Project:** api-center-demo — Azure API Center / APIM / Foundry demo platform for a utility company "Grid Maintenance Agent" narrative
- **Stack:** C# / ASP.NET Core Minimal APIs (.NET 10), OpenAPI
- **Created:** 2026-09-29

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->
- GridTelemetry.Api starts as a `dotnet new web` stub (weather forecast) — replace with `/substations` and `/substations/{id}/health` synthetic endpoints.
- Only synthetic data — no real grid/outage/customer data, per repo-wide constraint.
📌 Team update (2026-09-29T23:23:13-04:00): Lead standardized deployed app outputs as GRID_API_APP_URL/NAME and GRID_MCP_APP_URL/NAME, and Integration expects GridTelemetryApi__BaseUrl to point at the API app hostname in hosted environments — decided by Lead, Integration
📌 Team update (2026-09-29T23:23:13-04:00): Coordinator exposed /openapi/v1.json outside Development so the API contract can be imported from App Service during demos and registration — decided by Coordinator
