# API Center

Creates the API inventory with a system-assigned managed identity. Parameters:
`name`, `location`, `tags`, `skuName` (`Free` by default, or `Standard`).
Outputs: `id`, `name`, `principalId`.

The target plan for the demo is Standard. Initial provisioning explicitly sends
`sku.name: Free`. The live API requires SKU on updates even though the published
Bicep schema omits it; a property-scoped `BCP187` suppression bridges that schema
gap. Omitting SKU can fail repeat provisioning with "The Sku property on the
given model is null."

After provisioning and linking the Standard v2 APIM
instance with script 05, open the API Center in the Azure portal and select
**Overview > Manage plan > Standard plan > Submit**. Confirm the plan is Standard.
This is an in-place upgrade, not a resource replacement.
Then run `azd env set API_CENTER_SKU Standard` so subsequent deployments retain
the upgraded plan. Preflight blocks deploying Free over an existing Standard
instance and fails if its current plan cannot be determined.

API Center Standard is available at no extra cost while at least one eligible
APIM instance remains linked; Standard v2 qualifies. Without that link, review
Standard plan pricing before upgrading. See the
[upgrade instructions](https://learn.microsoft.com/azure/api-center/frequently-asked-questions#how-do-i-upgrade-my-api-center-from-the-free-plan-to-the-standard-plan)
and [linked-APIM benefit](https://learn.microsoft.com/azure/api-center/overview#standard-plan-benefit-when-api-center-linked-to-api-management).

Public access is intentional for this core-profile demo. Availability is checked
by preflight (East US 2 is not currently supported). API content and APIM
integration remain explicit demo steps, not deployment hooks.
