# Container Apps hosting

Creates a Consumption-only Azure Container Apps environment plus a shared
Azure Container Registry (Basic, admin user disabled) and a user-assigned
managed identity used for `AcrPull`. Two container apps are deployed —
`GridTelemetry.Api` and `GridTools.Mcp` — each with external HTTPS ingress on
port `8080`, a single active revision, and registry pulls authenticated via
the shared identity. This design was adopted after both Windows Basic (B1)
and Windows PremiumV4 (P0V4) App Service plans hit zero VM-family quota in
this subscription; Container Apps Consumption plans use a separate
vCPU-second billing/quota model that avoids that class of error.

Application Insights is wired through `APPLICATIONINSIGHTS_CONNECTION_STRING`
in each container's `env` array. The MCP app also receives
`GridTelemetryApi__BaseUrl`, pointed at the API app's ingress FQDN. Each
container app carries an `azd-service-name` tag (on top of the common tags)
so `azd deploy` can match it to the corresponding service in `azure.yaml`.

Both apps follow azd's `exists` parameter pattern: `apiAppExists` /
`mcpAppExists` (backed by the `SERVICE_<NAME>_RESOURCE_EXISTS` env vars azd
sets automatically) let `azd provision` reruns keep whatever image is
currently deployed instead of resetting it back to the placeholder image.
The read-only `current-images.bicep` nested deployment resolves these images
before either app is updated. Keeping the reads in a separate template avoids
ARM self-dependencies caused by referencing an app's current properties in
the same template that deploys it.
Before the first `azd deploy`, both apps run the placeholder image
(`mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`).

`location` is supplied by the caller and may differ from the rest of the
deployment's `location` (see `appHostingLocation` in `infra/main.bicep`). Some
subscriptions have zero VM-family quota for certain regions used for API
Center/APIM (East US, East US 2); this module can be pointed at a region with
available Container Apps Consumption quota (West US 3 by default) without
moving the rest of the demo.

| | |
|---|---|
| Kind | `composite` |
| Profiles | `core`, `full` |
| Abbreviation | `cae` (environment), `ca` (container apps) |
| Providers | `Microsoft.App` |
| Private endpoint | none |
| Feature flag | none — always deployed |

## Parameters

| Name | Type | Required | Notes |
|---|---|---|---|
| `containerAppsEnvironmentName` | string | yes | Container Apps managed environment name |
| `containerRegistryName` | string | yes | Globally unique, alphanumeric-only ACR name |
| `identityName` | string | yes | Shared user-assigned managed identity name |
| `apiAppName` | string | yes | GridTelemetry API container app name |
| `mcpAppName` | string | yes | GridTools MCP container app name |
| `location` | string | yes | Azure region |
| `tags` | object | yes | Common tags from `infra/core/tags.bicep` |
| `applicationInsightsConnectionString` | string | yes | Shared telemetry connection string |
| `logAnalyticsWorkspaceName` | string | yes | Log Analytics workspace backing the environment's logs |
| `apiAppExists` | bool | no (default `false`) | Preserves the API app's deployed image across `azd provision` reruns |
| `mcpAppExists` | bool | no (default `false`) | Preserves the MCP app's deployed image across `azd provision` reruns |

## Outputs

| Name | Notes |
|---|---|
| `apiAppName` | Grid Telemetry container app resource name |
| `apiAppUrl` | `https://<api-app-ingress-fqdn>` |
| `mcpAppName` | Grid Tools MCP container app resource name |
| `mcpAppUrl` | `https://<mcp-app-ingress-fqdn>` |
| `containerAppsEnvironmentName` | Container Apps environment resource name |
| `containerRegistryName` | Container registry resource name |
| `containerRegistryLoginServer` | Container registry login server (also surfaced as `AZURE_CONTAINER_REGISTRY_ENDPOINT`) |
| `identityId` | Shared user-assigned managed identity resource ID |

## Wire-up

```bicep
module appHosting 'modules/app-hosting/main.bicep' = {
  scope: resourceGroup
  name: 'app-hosting'
  params: {
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerRegistryName: containerRegistryName
    identityName: identityName
    apiAppName: apiAppName
    mcpAppName: mcpAppName
    location: appHostingLocation
    tags: tags
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    apiAppExists: apiAppExists
    mcpAppExists: mcpAppExists
  }
}
```
