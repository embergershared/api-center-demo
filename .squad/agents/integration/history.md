# Project Context

- **Owner:** Emmanuel
- **Project:** api-center-demo — Azure API Center / APIM / Foundry demo platform for a utility company "Grid Maintenance Agent" narrative
- **Stack:** C# (ModelContextProtocol.AspNetCore SDK), Microsoft Foundry Agent Service, APIM AI Gateway
- **Created:** 2026-09-29

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->
- GridTools.Mcp starts as a `dotnet new web` "Hello World" stub — needs real `AddMcpServer()`/`MapMcp()` wiring plus one tool that calls GridTelemetry.Api over HTTP.
- API Center supports registering MCP servers directly (Standard plan) via `az apic mcp-server` / the MCP registry; Foundry agents can be fronted by the APIM AI Gateway and then registered as APIs in API Center.
📌 Team update (2026-09-29T23:23:13-04:00): Backend finalized the REST contract for list and health queries, including camelCase payload fields and 404 behavior for unknown substations — decided by Backend
📌 Team update (2026-09-29T23:23:13-04:00): DevOps is wiring the hosted MCP server into Foundry using the published tool names list_substations and get_substation_health plus the new app output variables — decided by DevOps
