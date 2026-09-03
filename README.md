# Azure API Center Customer Demo Kit

A ready-to-run kit for a ~25–30 minute Azure API Center demo: single system of
record for every API — REST, GraphQL, gRPC, SOAP — no matter where it runs
(APIM, Functions, AKS, other clouds, on-prem).

## Prerequisites

- Azure CLI `>= 2.60` with the `apic-extension`:
  ```bash
  az extension add --name apic-extension --upgrade --allow-preview true
  ```
  APIM synchronization requires preview extension version `1.2.0b1` or later.
- `Contributor` and `Role Based Access Control Administrator` at subscription
  scope. The scripts create the resource group and grant API Center read-only
  access to APIM.
- A 3–4 character base value, publisher email, and publisher organization name
  for the API Management instance created by the demo.
- VS Code + the **Azure API Center** extension (marketplace) for the dev-tooling moment.
- `az login` completed, correct subscription set (`az account set -s <sub-id>`).

## Layout

```
scripts/   00-09 numbered PowerShell scripts, run in order, idempotent-ish
samples/   OpenAPI specs used to register APIs (v1 + v2, plus a "messy" one for linting)
docs/      talk track / cheat sheet to read from during the demo
```

## Quick start

### PowerShell (pwsh, Windows or cross-platform)

```powershell
cd scripts
. ./00-vars.ps1 `
  -BaseValue "jrf" `
  -PublisherEmail "api-team@contoso.com" `
  -PublisherName "Contoso"
./01-create-service.ps1
./02-metadata-schema.ps1
./03-register-openapi-api.ps1
./04-versions-and-deprecation.ps1
./05-link-apim.ps1
./06-environments-deployments.ps1
./07-lint-analysis.ps1
./08-portal-and-cli-demo.ps1
```

> Note: `00-vars.ps1` must be dot-sourced (`. ./00-vars.ps1 ...`) so the
> environment variables it sets persist in your shell session; the numbered
> scripts after it reuse those values when they dot-source it internally.

Each script announces the operation it performs before invoking Azure CLI.

Cleanup: `./99-cleanup.ps1`.

See `docs/TALK_TRACK.md` for the minute-by-minute narration mapped to each script.
