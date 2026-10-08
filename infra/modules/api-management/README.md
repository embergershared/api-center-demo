# API Management

Creates a public Standard v2 gateway with one capacity unit. Parameters: `name`, `location`, `tags`,
`publisherName`, `publisherEmail`, `apiCenterPrincipalId`. Outputs: `id`, `name`,
`gatewayUrl`. The resource-scoped API Management Service Reader assignment uses
a deterministic GUID and the API Center system-assigned identity.

The name follows the starter's global naming function with a six-character
subscription/environment/location hash and a 50-character budget. This module
does not configure private endpoints or virtual network integration.

The full profile also runs `ai-gateway.bicep` after Foundry, Redis, monitoring,
and the gateway exist. It configures account-scoped OpenAI User access for the
gateway identity, App Insights Metrics Publisher access, an identity-based
logger and API diagnostics, TLS external cache, chat and embeddings backends,
and the HTTPS `/ai/chat/completions` API with an API-scoped demo subscription.
The core profile remains an uninstrumented gateway with monitoring resources.

Both deployment profiles also run `mslearn-mcp.bicep`. It adds a governed APIM
passthrough MCP API with base path `/learn-mcp` and client endpoint
`/learn-mcp/mcp` that fronts Microsoft Learn's public,
read-only documentation MCP endpoint. Because it is a normal APIM `apis`
resource, the existing APIM↔API Center integration catalogs it automatically;
no extra API Center registration script is required.
Its streamable `mcpProperties.endpoints` is a `message`-keyed object: APIM's
runtime expects `Dictionary<string, McpEndpointContract>` even though the
[2025-09-01-preview template reference](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/2025-09-01-preview/service/apis)
currently describes an array. The Bicep `any()` escape is limited to this
property; the compiled ARM shape is checked in `tests/run-tests.ps1`.

The backend base URL is `https://learn.microsoft.com/api`, and the message
path is `/mcp`. APIM appends that path when forwarding requests, reaching
`https://learn.microsoft.com/api/mcp`. Including `/mcp` in both the backend
base and the message path produces an upstream 404.

For VS Code, use an HTTP MCP server with URL
`https://<apim-service-name>.azure-api.net/learn-mcp/mcp`
(also exported as `MSLEARN_MCP_URL`). Do not use `/learn-mcp/api/mcp`:
`/api` belongs to the upstream URL, not the gateway route. Update any saved
server URL and restart that server in VS Code after deploying this change.
If the server was added through API Center, inspect its deployment's
`server.runtimeUri`, not just the APIM API. The portal test console uses that
catalog URL. It must end in `/learn-mcp/mcp`. A working gateway and CORS
policy do not repair a stale catalog URL.

An errored APIM integration can leave the old `/learn-mcp/api/mcp` URL in
the catalog. Integration-owned runtime URLs cannot be changed independently:
an update may return successfully while leaving the old value unchanged.
Read back the deployment after any repair and initialize MCP using that exact
URL and the portal's Origin header.

`azd provision` runs `scripts/provision-catalog.ps1` after deployment for
independent catalog entries, then `scripts/05-link-apim.ps1` for synchronization. Duplicate
synchronized copies are intentional. Use `managed-mslearn-mcp` for portal
testing: its runtime URL is explicitly managed and checked on every run.
`managed-fleet-vehicle` includes the Fleet v2 specification, and
`managed-utility-ai` includes the AI specification in the `full` profile.
The `core` profile omits Utility AI because it does not deploy the AI gateway.
The independent records use a separate `managed-apim` environment and no
`apiSourceId`; Azure-generated synchronization records cannot take ownership.
Provisioning never deletes previously restored entries.

The link step verifies the API Center identity and its APIM-scoped Reader role
before creating a missing integration. It retries permission propagation and
reuses any existing link to this APIM, including a snapshot-named link. It
checks the source and system-assigned identity, waits up to ten minutes for
`syncing`, and fails on errors or a timeout rather than claiming successful sync.
It does not unlink/recreate a failing integration, which would delete its
catalog records. Back up linked definitions and metadata before any manual
unlink. Removing the link can end the linked-APIM Standard-plan pricing benefit.

`mslearn-mcp-policy.xml` enables browser testing only from the API Center
portal's HTTPS origin. The `apiCenterPortalHostname` parameter is wired to
the API Center resource's actual `portalHostname` output, not a hard-coded
environment name. CORS runs before inherited inbound policies, permits
GET/POST/DELETE and MCP request headers, and exposes the session/protocol
response headers without enabling browser credentials or wildcard origins.
For a standalone deployment of `mslearn-mcp.bicep`, supply both
`apiManagementName` and `apiCenterPortalHostname`.

`openapi.json` restricts demo calls to bounded, non-streaming text completions.
`ai-policy.xml` validates this schema, removes client keys before forwarding,
partitions the semantic cache by subscription/deployment/token budget, applies
request/token limits, emits backend token metrics, and authenticates to Foundry
with managed identity. Cache entries expire after 60 seconds. System messages
participate in similarity matching. Do not use this cache for real operational
utility data or safety-critical decisions; see `docs/AI_GATEWAY.md`.

Standard v2 has ongoing provisioned-capacity charges. An existing Consumption
instance cannot be upgraded in place to Standard v2; deploy a new environment
and rerun the demo content scripts. See the
[v2 tier migration limitations](https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview#frequently-asked-questions).
