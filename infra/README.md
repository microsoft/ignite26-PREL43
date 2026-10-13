# infra

| Path | What it is |
|---|---|
| `config/tenant.example.yaml` | Configuration template; copy to `tenant.yaml` at the repository root |
| `entra/app-permissions.json` | Microsoft Graph application permissions and directory roles the engine needs |
| `entra/setup-app-registration.ps1` | Creates the app registration with a certificate credential, grants admin consent, assigns the two directory roles |

## Set up the app registration

Run once per tenant as a tenant administrator, with the Microsoft Graph PowerShell SDK installed:

```powershell
./infra/entra/setup-app-registration.ps1 -TenantId <tenant-id> -CertificatePath ./vs-hydration.cer
```

The script only uploads the public certificate. Keep the private key in the key vault and place the PEM (key and certificate) on the runner host at the path set in `auth.certificate_path`.

## Runner host

Any Linux, Windows or macOS machine or VM with Python 3.11+ and outbound HTTPS to `login.microsoftonline.com` and `graph.microsoft.com`. No inbound ports. 2 vCPU and 4 GB are enough; Microsoft Graph throttling sets the pace.

```bash
pip install ./src/engine
vs-hydrate validate --config tenant.yaml
```
