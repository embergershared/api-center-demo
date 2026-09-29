# Microsoft Foundry

Creates an `AIServices` S0 account, a child project, and `chat` / `embeddings`
model deployments. This is modern Foundry, not a classic Machine Learning hub.
Public networking is enabled; key authentication is disabled. APIM receives
account-scoped Cognitive Services OpenAI User access in the gateway module.
The project's system identity also receives account-scoped model access.

Provisioning is serialized as account -> project -> chat -> embeddings.
Project and model writes can contend for the account's operation lock, so
depending on the account alone is insufficient to prevent `RequestConflict`.

Model names, explicit versions, deployment SKUs, capacities, and location come
from the root template. Preflight checks the subscription's live model catalog
and quota. Versions are pinned (no automatic upgrade); revisit them before
retirement. GlobalStandard uses global inference routing, not a regional
data-residency guarantee. No provisioned-throughput deployments are created.

Grant human demo operators Azure AI User at this account/project as appropriate
before using the Foundry playground; infrastructure Contributor alone does not
provide model data-plane access. No human principal is granted access implicitly.
