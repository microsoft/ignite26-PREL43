# Security

## Reporting a vulnerability

Do not open a public issue for security problems. Report them privately to the VectorSense maintainers through the security contact named in your licence agreement, with the release version, what you found and how to reproduce it.

## How the kit handles credentials and data

- The engine authenticates with a certificate credential only; client secrets are not supported.
- Credentials and the certificate stay with the lab host. VectorSense never receives tenant access.
- The engine reads from and writes to the configured tenant only and sends no data anywhere else.
- `out/seat-inventory.json` contains Temporary Access Passes. It is written with owner-only permissions; store it in a key vault, not a shared folder, and delete it after the event.
- App permissions are limited to the Microsoft Graph application permissions in `infra/entra/app-permissions.json` and the User Administrator and License Administrator roles.
- All lab data is fictional; seats hold no real personal data.
