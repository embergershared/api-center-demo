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
