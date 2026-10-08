# Utility AI gateway setup and walkthrough

## Deployment settings

Set overrides with `azd env set NAME value` before preview/provisioning.
`infra/main.parameters.json` is the source of defaults used by preflight.

| Setting | Default | Meaning |
|---|---|---|
| `DEPLOYMENT_PROFILE` | `full` | `core` excludes the new AI layer |
| `API_CENTER_SKU` | `Standard` | Set `Free` explicitly to use the limited Free plan; Standard can incur charges until an eligible APIM link is established |
| `AI_LOCATION` | seeded from `AZURE_LOCATION` | Foundry and both models |
| `CACHE_LOCATION` | seeded from `AZURE_LOCATION` | Managed Redis |
| `CHAT_MODEL_NAME` / `CHAT_MODEL_VERSION` | `gpt-5.6-luna` / `2026-07-09` | Explicit model/version, no automatic upgrade |
| `CHAT_DEPLOYMENT_SKU` | `GlobalStandard` | PAYG; `Standard` is the regional alternative |
| `CHAT_CAPACITY` | `10` | Model capacity units, not provisioned throughput |
| `EMBEDDING_MODEL_NAME` / `EMBEDDING_MODEL_VERSION` | `text-embedding-3-small` / `1` | Embeddings for cache lookup |
| `EMBEDDING_DEPLOYMENT_SKU` | `GlobalStandard` | PAYG; global inference routing, including when the account is in Central US |
| `EMBEDDING_CAPACITY` | `10` | Model capacity units |
| `REDIS_SKU` | `Balanced_B0` | `Balanced_B1` is also allowed |
| `REDIS_HIGH_AVAILABILITY` | `false` | Demo-only; enabling HA increases cost |
| `AI_TOKENS_PER_MINUTE` | `5000` | Per-APIM-subscription backend token rate |
| `AI_TOKENS_PER_DAY` | `100000` | Per-APIM-subscription daily backend token quota |

Model capacity units have model-specific TPM/RPM mappings. They are not dollar
budgets. The template never creates ProvisionedManaged deployments. Model
availability, retirement dates, quota, and current SKU/region support must be
checked for the target subscription. Use:

```powershell
. .\scripts\deployment-context.ps1
$values = Get-DeploymentEnvironment
$aiLocation = Get-DeploymentParameterValue $values 'aiLocation'
$subscriptionId = Get-DeploymentValue $values 'AZURE_SUBSCRIPTION_ID'
az cognitiveservices model list --location $aiLocation --subscription $subscriptionId --output json
az cognitiveservices usage list --location $aiLocation --subscription $subscriptionId --output table
```

Central US lists `GlobalStandard`, not regional `Standard`, for
`text-embedding-3-small` version `1` in the live AIServices/S0 catalog checked
on 2026-10-08. Existing environments retain their saved SKU; to migrate an
environment pinned to `Standard`, explicitly select it and run:

```powershell
azd env set EMBEDDING_DEPLOYMENT_SKU GlobalStandard
.\scripts\01-create-service.ps1 -PreviewOnly
```

`GlobalStandard` can process inference globally; it is not a regional-only
processing guarantee. Keep `Standard` only where the live catalog and quota
support it. Preflight reports catalog alternatives but never switches SKUs
automatically.

Preflight selects the `AIServices`/`S0` catalog entry used by the Foundry
template, then matches the base-model SKU's quota identifier
(`OpenAI.<deployment-SKU>.<model-name>`). Azure can also return classic `OpenAI`
account entries and fine-tuning SKUs with the same model/SKU names; these are
not substitutes for the base deployment. The selected account kind and quota
identifier are printed for diagnosis. Preflight still rejects genuinely
ambiguous/missing base-model entries, retired models, models without Chat
Completions support, invalid capacities, and insufficient available quota.
Deprecating models cannot be used for new or resized deployments even when
their inference retirement date is still in the future.
Repeat provisioning credits unchanged deployments in the recorded Foundry
account instead of double-counting their capacity. If an interrupted deployment
created models before outputs were saved, inspect those allocations and recover
the environment outputs before retrying; do not delete resources blindly.
Availability checks are not capacity reservations. If changing the chat model,
select a Chat Completions model that supports `max_completion_tokens` and
`reasoning_effort: none`;
this intentionally narrow demo API is not a universal proxy for reasoning,
image, tool, or streaming APIs.

### GPT-5 migration

The demo schema is now version 2.0.0: replace `max_tokens` with
`max_completion_tokens` and replace `temperature` with `reasoning_effort: none`.
Old payloads are rejected rather than silently forwarding unsupported options.
The gateway uses OpenAI's `/openai/v1/chat/completions` endpoint and injects the
fixed deployment name; clients cannot select another model. The 512-token
request ceiling and per-subscription semantic-cache isolation are unchanged.
The cache also varies by the completion-token limit and model/version.
See [Azure OpenAI reasoning model requirements](https://learn.microsoft.com/azure/foundry/openai/how-to/reasoning).

Existing azd environments keep their explicitly pinned values. To opt into the
new model before preview:

```powershell
azd env set CHAT_MODEL_NAME gpt-5.6-luna
azd env set CHAT_MODEL_VERSION 2026-07-09
.\scripts\01-create-service.ps1 -PreviewOnly
```

## One-time portal steps

1. API Center is provisioned on Standard by default. The postprovision hook
   runs script 05 to establish or verify the APIM link; rerun it to inspect
   an existing link after a failed hook. Standard may be billed until
   that link is established. Only an environment explicitly pinned to Free
   needs the portal upgrade and `azd env set API_CENTER_SKU Standard` afterward.
2. Open the modern Foundry project identified by `AZURE_AI_PROJECT_ENDPOINT`.
   An administrator must assign demo operators appropriate **Azure AI User**
   access to the account/project. Generic infrastructure Contributor is not a
   substitute for model data-plane permissions. No operator principal is
   implicitly assigned by these templates.
3. In Application Insights, enable **Usage and estimated costs > Custom metrics
   (Preview) > With dimensions**. The templates already configure the gateway
   identity, Monitoring Metrics Publisher role, logger, and API diagnostic
   `metrics: true`. See [the required custom-metrics setting](https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights#emit-custom-metrics).
4. In APIM **Subscriptions**, use `utility-ai-demo`, scoped to the `utility-ai`
   API. For script 09, copy its key privately and paste it only into the secure
   prompt. For the API Center portal's **Try this API**, `azd provision` also
   stores the generated subscription key in a demo Key Vault as
   `utility-ai-subscription-key` and grants API Center secret-reader access.
   Add an API Key authorization configuration with header
   `Ocp-Apim-Subscription-Key`, attach it to the synchronized API version,
   and grant the presenter credential access in the API Center portal; the
   published ARM/CLI API does not provision those three UI settings.
   Do not commit keys, put them in query strings, print them in terminal
   commands, or use an all-APIs admin subscription for the demo.

The API's HTTP endpoint is `AI_GATEWAY_URL`; the actual APIM host comes from
deployment outputs. Model and cache keys are not required by the caller.
RBAC propagation can delay the first successful model or telemetry call.

## Demonstration

Run `.\scripts\09-ai-gateway-demo.ps1 -Confirm` from the repo root.
The script sends the same harmless, synthetic glossary prompt twice, with
streaming disabled and at most 128 completion tokens. It prints status,
elapsed time, completion ID, and usage, but not the key or model response text.
An HTTP error stops the demonstration rather than reporting a cache success.

Use APIM's Test console and authorized request tracing to prove a cache hit:
look for the `llm-semantic-cache-lookup` result and whether forwarding to the
chat backend was skipped. A repeated completion ID is a useful clue, not an
independent guarantee. Lower latency alone proves nothing. Do not enable
subscription-wide tracing; use the portal's authorized, short-lived tracing
mechanism and only synthetic prompts.

The cache is partitioned by APIM subscription, fixed chat deployment, configured
model names/versions, and
requested completion-token bound. Temperature is constrained to 0 and system
messages remain part of similarity matching. The threshold is 0.05 (lower is
stricter), with a 60-second TTL. A cache hit can contain the original response's
usage numbers even though no new chat completion was billed. Embedding calls
for lookup still consume resources and are not counted as chat tokens by the
gateway's token metric.

Token metrics and `BackendRequests` are emitted after cache lookup, on the
backend path. Application Insights request telemetry still describes the API
calls. Daily quota returns 403; token/request throttles return 429. To
demonstrate throttling, temporarily lower `AI_TOKENS_PER_MINUTE`, preview and
reprovision, then use distinct synthetic prompts (or wait for cache expiry).
Restore the normal limit after the demonstration. Concurrent requests can
temporarily overshoot token limits; they are not hard billing caps.

In the Foundry playground, model requests go **directly to Foundry**, bypassing
APIM controls. Use the APIM endpoint when demonstrating gateway governance.
The project is ready for authorized users to create workflows/agents, but this
repository does not deploy an autonomous operational agent, tools, or RAG data.

## Operational queries

Open the deployed Log Analytics workspace, then **Logs**. Allow telemetry
ingestion time. Requests/metrics must exist before these queries return rows.

```kusto
AppRequests
| where TimeGenerated > ago(1h)
| where Url contains "/ai/chat/completions"
| summarize Requests=count(), Failures=countif(Success == false),
    P95DurationMs=percentile(DurationMs, 95)
    by bin(TimeGenerated, 5m), ResultCode
| order by TimeGenerated asc
```

Discover the actual emitted metric names rather than assuming fixed naming:

```kusto
AppMetrics
| where TimeGenerated > ago(1h)
| summarize Samples=sum(ItemCount), Total=sum(Sum) by Name
| order by Name asc
```

In Application Insights **Metrics**, select the `UtilityAIGateway` custom
namespace and inspect token metrics and `BackendRequests` by API/operation.
These are usage observations, not a dollar estimate. A daily ingestion cap is
not a hard cost cap, and hitting it can create telemetry gaps.

## Boundaries and troubleshooting

- APIM cache validation can report "Value should represent absolute http URL"
  for `properties.resourceId`. This field requires the Redis resource's
  absolute management URL, not its `/subscriptions/...` ARM ID. The template
  combines the active Azure cloud's Resource Manager endpoint with the cache
  ID using `uri()`. This is a management reference, not the Redis connection
  string or a model endpoint. See the
  [APIM cache request example](https://learn.microsoft.com/rest/api/apimanagement/cache/create-or-update?view=rest-apimanagement-2024-05-01).
- Foundry `RequestConflict` ("Another operation is in progress") indicates
  overlapping writes on the account, not necessarily an invalid project.
  The template serializes account -> project -> chat -> embeddings to avoid
  sibling operations colliding. If another deployment is still writing to
  the same account, wait for it to finish before rerunning
  `.\scripts\01-create-service.ps1` and approving its preview. Do not start
  simultaneous retries or delete successful resources. If the conflict
  persists with no active deployment, inspect the account's provisioning
  state and deployment operations before retrying.
- Public endpoints remain authenticated: callers use APIM subscription keys;
  APIM uses Entra identity and account-scoped OpenAI User access. Foundry local
  key authentication is disabled. Redis uses its access key over TLS because
  the APIM external-cache resource accepts a connection string.
- Cache keys are read by ARM directly into the APIM cache property, never
  exported via module/azd outputs. Rotate Redis keys deliberately and
  reprovision the gateway connection; restrict access to deployment and APIM
  administration.
- No request/response bodies, headers, or client IPs are configured for AI API
  telemetry. Do not add secrets to request URLs. Keep demo subscriptions
  separate for callers who should not share cached results.
- Non-HA Redis can lose entries or be unavailable during maintenance.
  RediSearch is created up front with Enterprise clustering and NoEviction.
  When memory fills, writes fail instead of evicting indexed entries. Check
  Redis memory/cache errors; do not infer successful caching from HTTP 200.
- Cache similarity is not correctness. Never cache real outage status, outage
  restoration plans, equipment switching instructions, or sensitive customer
  data. NERC-CIP metadata is not a compliance assessment or certification.
- 401: check the API-specific subscription key. 403: check quota/Foundry RBAC.
  429: inspect gateway/backend rate and token limits. 5xx: inspect APIM trace,
  backend availability, Redis connectivity, and identity propagation.
- No preview/compile can prove live policy behavior, model availability at
  deployment time, portal access, or telemetry ingestion. Confirm these with
  the deployed smoke test and portal checks before presenting.

References: [semantic-cache requirements](https://learn.microsoft.com/azure/api-management/azure-openai-enable-semantic-caching),
[token limits](https://learn.microsoft.com/azure/api-management/llm-token-limit-policy),
[token metrics](https://learn.microsoft.com/azure/api-management/llm-emit-token-metric-policy),
[Foundry resource types](https://learn.microsoft.com/azure/ai-foundry/concepts/resource-types).
