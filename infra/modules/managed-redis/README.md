# Azure Managed Redis

The full profile deploys Balanced B0 (B1 optional) with RediSearch at creation,
Enterprise clustering, NoEviction, TLS 1.2, and port 10000. This is **not** Basic
C0 Azure Cache for Redis; Basic cannot provide the required vector search.

Non-HA is the demo default and has no availability SLA. Enable HA for greater
availability, but it increases cost and cannot subsequently be disabled in place.
Modules and clustering choices may also require recreation to change.
NoEviction means full memory rejects new writes; monitor memory and cache
errors. The demo policy expires cached responses after 60 seconds.

APIM's external-cache connection uses the database access key, retrieved by ARM
directly into the APIM cache property. No keys appear in template outputs or
azd environment outputs. Treat cache-management access as privileged; rotate
keys deliberately and reprovision the gateway configuration after rotation.
