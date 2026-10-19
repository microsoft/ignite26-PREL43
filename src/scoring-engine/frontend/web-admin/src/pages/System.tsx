import { CheckCircle2, History, Plug, XCircle } from "lucide-react";
import { PageHeader } from "../components/Layout";
import { ErrorAlert, Loading } from "@shared/components/ui";
import { api } from "../lib/api";
import { config } from "@shared/lib/config";
import { dateTime } from "@shared/lib/format";
import { useLoad } from "@shared/lib/hooks";

interface GraphStatus { ok: boolean; mode?: string; tenant_id?: string; tenant_name?: string; domains?: string[]; error?: string; mock_file?: string; mock_users?: number }
interface Audit { id: number; actor: string; action: string; target_type: string | null; target_id: string | null; details: Record<string, unknown>; created_at: string }

const PERMISSIONS = [
  ["Files.Read.All", "OneDrive / SharePoint outputs (Cowork saves to the user's OneDrive Cowork folder)"],
  ["Mail.ReadBasic.All", "Sent mail subject, recipients, attachment flag (Mail.Read if body checks are needed)"],
  ["Calendars.ReadBasic.All", "Meetings created by the participant"],
  ["ChannelMessage.Read.All", "Teams channel posts"],
  ["User.Read.All", "Resolve lab UPNs to object IDs"],
  ["GroupMember.Read.All", "Read an event's lab-account roster from an Entra group (Microsoft 365 sync)"],
  ["AiEnterpriseInteraction.Read.All", "Copilot interaction export (prompts and responses)"],
  ["AuditLogsQuery.Read.All", "Purview CopilotInteraction audit records (deferred checks)"],
];

export default function System() {
  const graph = useLoad(() => api.get<GraphStatus>("/api/admin/graph/status"));
  const audit = useLoad(() => api.get<Audit[]>("/api/admin/audit?limit=100"));
  const cfg = config();

  return (
    <>
      <PageHeader crumbs={[{ label: "System" }]} title="System" sub="Evidence source, Microsoft Graph permissions and the admin audit trail." />
      <div className="stack">
        <div className="grid grid-2" style={{ alignItems: "start" }}>
          <div className="card">
            <div className="card-head"><h3 className="row"><Plug size={16} /> Microsoft Graph connection</h3></div>
            <div className="card-pad">
              {!graph.data ? <Loading /> : (
                <dl className="kv">
                  <dt>Status</dt>
                  <dd className="row">{graph.data.ok ? <><CheckCircle2 size={16} color="var(--ok)" /> Connected</> : <><XCircle size={16} color="var(--bad)" /> {graph.data.error}</>}</dd>
                  <dt>Mode</dt><dd>{graph.data.mode === "mock" ? "Mock evidence (local testing)" : "Live tenant"}</dd>
                  <dt>Tenant</dt><dd>{graph.data.tenant_name ?? "—"} {graph.data.tenant_id && <code className="faint">{graph.data.tenant_id}</code>}</dd>
                  {graph.data.domains && <><dt>Domains</dt><dd>{graph.data.domains.join(", ")}</dd></>}
                  {graph.data.mock_file && <><dt>Mock file</dt><dd><code>{graph.data.mock_file}</code> · {graph.data.mock_users} users</dd></>}
                  <dt>Admin sign-in</dt><dd>{cfg.auth_mode === "entra" ? "Microsoft Entra ID" : "Local (test only)"}</dd>
                </dl>
              )}
            </div>
          </div>
          <div className="card">
            <div className="card-head"><h3>Required Graph application permissions</h3></div>
            <table className="plain">
              <tbody>
                {PERMISSIONS.map(([p, why]) => (
                  <tr key={p}><td><code>{p}</code></td><td className="small muted">{why}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
        <div className="card">
          <div className="card-head"><h3 className="row"><History size={16} /> Audit log</h3><span className="faint small">Last 100 admin actions</span></div>
          <ErrorAlert error={audit.error} />
          {!audit.data ? <Loading /> : (
            <div className="table-wrap">
              <table className="table">
                <thead><tr><th>When</th><th>Who</th><th>Action</th><th>Target</th><th>Details</th></tr></thead>
                <tbody>
                  {audit.data.length === 0 && <tr><td colSpan={5} className="faint">No admin actions yet.</td></tr>}
                  {audit.data.map((a) => (
                    <tr key={a.id}>
                      <td className="small faint">{dateTime(a.created_at)}</td>
                      <td>{a.actor}</td>
                      <td><code>{a.action}</code></td>
                      <td className="small">{a.target_type} <span className="faint mono">{a.target_id?.slice(0, 8)}</span></td>
                      <td className="small muted mono">{Object.keys(a.details).length ? JSON.stringify(a.details) : ""}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
