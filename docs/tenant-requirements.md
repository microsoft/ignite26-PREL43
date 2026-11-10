# Participant tenant requirements

What every participant tenant (and the dev/test tenant) must have. The **Pre-flight check** life cycle
action verifies all of it before anything is written, and ends the lab with a list of whatever is missing.

## Cloud credential: Microsoft Graph application permissions

| Needed for | Permission (any one listed satisfies the line) |
|---|---|
| Hydration: personas and learner profile | `User.ReadWrite.All` or `Directory.ReadWrite.All` |
| Hydration: mail | `Mail.ReadWrite` |
| Hydration: calendar | `Calendars.ReadWrite` |
| Hydration: mailbox time zone | `MailboxSettings.ReadWrite` |
| Hydration: channel files | `Files.ReadWrite.All` or `Sites.ReadWrite.All` |
| Hydration: Teams import (backdated posts) | `Teamwork.Migrate.All` |
| Hydration: the Helix team (group) | `Group.ReadWrite.All` or `Directory.ReadWrite.All` |
| Hydration: team membership | `TeamMember.ReadWrite.All` |
| Readiness: count channel messages | `ChannelMessage.Read.All` |
| Scoring: learner mail, calendar, OneDrive | `Mail.Read`, `Calendars.Read`, `Files.Read.All` (or their ReadWrite forms) |
| Learner: Copilot licence for the admin | `Organization.Read.All` (or `Directory.Read.All`) to read licences; `User.ReadWrite.All` to assign |

## Users and licences

- The **Office 365 admin** is the learner. It needs a licence that includes Copilot (the Learner step assigns one from a
  free seat, or from a spare user) and gets a mailbox and OneDrive.
- **Prepaid Copilot credits** (a Capacity Pack) in the tenant. The Credits step switches Cowork on by creating a spending policy
  billed to them; it cannot add credits.
- Microsoft's **Copilot Cost Management API preview** (Graph beta) available in the tenant, and an admin that can sign in
  from a script (no MFA or Conditional Access block).
- **At least 6 other licensed users with mailboxes**, plus a spare seat if the admin is unlicensed. They are renamed to the Helix meeting organisers
  (Chloe Martin, Elena Marsh, Ethan Brooks, Grace Liu, Nadia Kowalski, Tomás Rivera); their UPNs don't change.
  Admin accounts are never used as organisers.
- The other 26 Helix personas and the "Helix Reviewer" are created as **unlicensed, sign-in-disabled** accounts.

## Event settings

Set at the top of the *Prepare Helix workspace* life cycle script:

| Setting | Example | Notes |
|---|---|---|
| `$EventDate` | `2026-11-18` | Day D of the Helix timeline; left as `YYYY-MM-DD`, a launch uses today |
| `$EventTimeZone` | `India Standard Time` | Windows time zone name |

## Lab VM

- The HelixKit ISO is in the VM's DVD drive at start (Virtual Machines tab → DVD Drive: HelixKit Media).
- Outbound HTTPS to `login.microsoftonline.com` and `graph.microsoft.com`.

## Missing permissions: the Grant step

If the credential lacks any permission above, the life cycle script's **Grant** step adds it in that
launch's tenant, signed in as the tenant admin (`@lab.CloudCredential(WWLM365E7).Username` / `.Password`,
falling back to `admin@<TenantName>`), and waits until the app's token carries it. This needs an admin
account **without MFA or Conditional Access** on script sign-in. The lasting fix is still the credential
template: with the permissions there, Grant does nothing and no admin password is used.

## Timing

Hydration runs only from **D−1 09:30 to the end of D** in `EventTimeZone` (Teams import refuses
future-dated posts). Pre-build lab instances inside that window.
