# API Center

Creates the API inventory with a system-assigned managed identity. Parameters:
`name`, `location`, `tags`, `skuName` (`Standard` by default, or explicit `Free`).
Outputs: `id`, `name`, `principalId`, `portalHostname` (used for the Learn MCP
API's portal-only CORS policy). The live API returns `portalHostname` despite
its absence from the published Bicep schema; a property-scoped `BCP053`
suppression permits reading that output.

Initial provisioning explicitly sends `sku.name: Standard` by default. The live API requires SKU on updates even though the published
Bicep schema omits it; a property-scoped `BCP187` suppression bridges that schema
gap. Omitting SKU can fail repeat provisioning with "The Sku property on the
given model is null."

For environments explicitly set to `API_CENTER_SKU=Free`, link the Standard v2
APIM instance with script 05, then select **Overview > Manage plan > Standard
plan > Submit** in the portal. After confirming the upgrade, run
`azd env set API_CENTER_SKU Standard` to preserve it on subsequent deployments.
Preflight blocks deploying Free over an existing Standard instance and fails
if its current plan cannot be determined.

API Center Standard is available at no extra cost while at least one eligible
APIM instance remains linked; Standard v2 qualifies. A fresh Standard deployment
may incur Standard charges until the postprovision link is established. See the
[upgrade instructions](https://learn.microsoft.com/azure/api-center/frequently-asked-questions#how-do-i-upgrade-my-api-center-from-the-free-plan-to-the-standard-plan)
and [linked-APIM benefit](https://learn.microsoft.com/azure/api-center/overview#standard-plan-benefit-when-api-center-linked-to-api-management).

Public access is intentional for this core-profile demo. Availability is checked
by preflight (East US 2 is not currently supported). API content for the three
managed demo entries is configured by `scripts/provision-catalog.ps1` in azd's
postprovision hook. The hook then runs `05-link-apim.ps1` to verify the live
API Center principal and plan, check its APIM-scoped Reader assignment, and
create or reuse the synchronization link. Identity and RBAC remain owned by
Bicep; the script retries permission propagation without changing either.
The script must observe `syncing` within ten minutes or the hook fails with
diagnostics. It never resets or deletes an existing link, and can be rerun
independently after resolving an error. The sync environment is selected by
Azure, never the independently managed catalog environment.
Fleet and Learn MCP are always registered; Utility AI follows the full profile.
Other sample registrations remain explicit demo steps.
