# VS Code publish walkthrough

Use this short operator flow when the demo switches from scripted registration to the VS Code experience.

## Publish `GridTelemetry.Api` to Container Apps

1. Open the repo in VS Code and sign in to the Azure extension with the same subscription used for this demo environment.
2. Run `azd deploy grid-telemetry-api` from a terminal (VS Code's App Service **Deploy to Web App** command does not apply to Container Apps) — this builds the container image, pushes it to the demo's Azure Container Registry, and updates the `GridTelemetry.Api` container app revision.
3. Confirm the deployment output and wait for the new revision to become active.
4. After publish completes, browse to `$GRID_API_APP_URL/openapi/v1.json` (the value of the `GRID_API_APP_URL` deployment output) to confirm the live OpenAPI document is reachable before running script 10.

## Register it in API Center from VS Code

1. Install the **Azure API Center** VS Code extension if it is not already installed.
2. Open the downloaded or generated OpenAPI file you want to register, or export the live API description into a local file first.
3. From the Command Palette, choose **Azure API Center: Register API** > **Manual**.
4. Select this demo's API Center and use `samples\grid-telemetry-v1.json` as the definition file when prompted. Enter **Grid Telemetry API** as the title and choose REST; complete the version and definition prompts.
5. Verify the API appears in API Center search next to the other demo assets. In the Azure portal, edit its metadata to set **Lifecycle stage** to `production` and **Business owner** to `Grid Operations Team`.

Script 02 keeps these custom fields optional on API registration because the
VS Code registration prompts do not collect them. If an existing API Center
still reports "The provided metadata is missing one or more required
properties", rerun `.\scripts\02-metadata-schema.ps1` against the intended azd
environment before retrying registration. Check **API Center > Governance >
Metadata** for any other required API fields configured outside this demo.
