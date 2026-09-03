# Azure API Center Customer Demo Kit

A ready-to-run kit for a ~25–30 minute Azure API Center demo: single system of
record for every API — REST, GraphQL, gRPC, SOAP — no matter where it runs
(APIM, Functions, AKS, other clouds, on-prem).

## Prerequisites

- Azure CLI `>= 2.60` with the `apic-extension`:
  ```bash
  az extension add --name apic-extension --upgrade
  ```
- An Azure subscription with `Contributor` on the target resource group.
- (Optional, for APIM sync step) an existing Azure API Management instance.
- VS Code + the **Azure API Center** extension (marketplace) for the dev-tooling moment.
- `az login` completed, correct subscription set (`az account set -s <sub-id>`).

## Layout

```
scripts/   00-09 numbered, run in order, idempotent-ish — provided as both
           bash (*.sh) and PowerShell (*.ps1); use whichever matches your shell
samples/   OpenAPI specs used to register APIs (v1 + v2, plus a "messy" one for linting)
docs/      talk track / cheat sheet to read from during the demo
```

## Quick start

### bash / zsh

```bash
cd scripts
chmod +x *.sh
./00-vars.sh            # edit subscription/region/names first!
./01-create-service.sh
./02-metadata-schema.sh
./03-register-openapi-api.sh
./04-versions-and-deprecation.sh
./05-link-apim.sh        # optional, needs an existing APIM instance
./06-environments-deployments.sh
./07-lint-analysis.sh
./08-portal-and-cli-demo.sh
```

### PowerShell (pwsh, Windows or cross-platform)

```powershell
cd scripts
. ./00-vars.ps1          # dot-source; edit subscription/region/names first!
./01-create-service.ps1
./02-metadata-schema.ps1
./03-register-openapi-api.ps1
./04-versions-and-deprecation.ps1
./05-link-apim.ps1       # optional, needs an existing APIM instance
./06-environments-deployments.ps1
./07-lint-analysis.ps1
./08-portal-and-cli-demo.ps1
```

> Note: `00-vars.ps1` must be dot-sourced (`. ./00-vars.ps1`) so the
> environment variables it sets persist in your shell session; the numbered
> scripts after it dot-source it internally, so you only need to do this once
> if you also want to inspect the vars yourself.

Each script echoes the `az` commands it runs so you can also copy/paste
individual lines live during the demo instead of executing the script wholesale.

Cleanup: `./99-cleanup.sh` or `./99-cleanup.ps1`.

See `docs/TALK_TRACK.md` for the minute-by-minute narration mapped to each script.
