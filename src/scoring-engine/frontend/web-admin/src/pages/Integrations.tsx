import { useState } from "react";
import { Activity, Ban, KeyRound, Pencil, PlugZap, Plus, RefreshCw, RotateCcw, Webhook } from "lucide-react";
import { PageHeader } from "../components/Layout";
import { CopyButton, Empty, ErrorAlert, Loading, Modal, SecretField, Stat, StatusBadge } from "@shared/components/ui";
import { api, ApiError } from "../lib/api";
import { config } from "@shared/lib/config";
import { dateTime, relTime } from "@shared/lib/format";
import { useLoad } from "@shared/lib/hooks";
import type { Integration } from "@shared/lib/types";

type Revealed = { title: string; integration: Integration };

export default function Integrations() {
  const { data, error, reload } = useLoad(() => api.get<Integration[]>("/api/admin/integrations"));
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<Integration | null>(null);
  const [revealed, setRevealed] = useState<Revealed | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  async function act(fn: () => Promise<Integration | void>, title?: string) {
    setActionError(null);
    try {
      const result = await fn();
      if (result && title) setRevealed({ title, integration: result });
      await reload();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : String(e));
    }
  }

  const active = (data ?? []).filter((i) => i.status === "active");
  return (
    <>
      <PageHeader
        crumbs={[{ label: "Integrations" }]}
        title="Integrations"
        sub="Client credentials for lab partners calling the scoring API."
        actions={<button className="btn btn-primary" onClick={() => setCreating(true)}><Plus size={16} /> New Integration</button>}
      />
      <div className="stack">
        <ErrorAlert error={error ?? actionError} />
        {!data ? <Loading /> : (
          <>
            <div className="grid grid-4">
              <Stat tone="blue" icon={<KeyRound size={16} />} value={data.length} label="All Integrations" foot={`${active.length} active now`} />
              <Stat tone="orange" icon={<PlugZap size={16} />} value={active.filter((i) => i.last_used_at).length} label="Connected" foot="Token requested at least once" />
              <Stat tone="purple" icon={<Activity size={16} />} value={data.reduce((n, i) => n + (i.submissions ?? 0), 0).toLocaleString()} label="Submissions" foot="Complete calls received" />
              <Stat tone="pink" icon={<Webhook size={16} />} value={data.filter((i) => i.webhook_url).length} label="Webhooks" foot="Vendors receiving pushed results" />
            </div>
            <div className="card">
              {data.length === 0 ? (
                <Empty icon={<KeyRound size={20} />} title="No integrations yet">
                  Create one per lab vendor. They receive a client ID and secret to call the API.
                </Empty>
              ) : (
                <div className="table-wrap" style={{ paddingTop: 14 }}>
                  <table className="table">
                    <thead>
                      <tr><th>Integration</th><th>Client ID</th><th>Secret</th><th>Results</th><th>Usage</th><th>Status</th><th className="num">Actions</th></tr>
                    </thead>
                    <tbody>
                      {data.map((i) => (
                        <tr key={i.id}>
                          <td>
                            <div className="row">
                              <span className="avatar">{i.vendor.slice(0, 2).toUpperCase()}</span>
                              <div><div style={{ fontWeight: 500 }}>{i.name}</div><div className="cell-sub">{i.vendor} · created {dateTime(i.created_at)}</div></div>
                            </div>
                          </td>
                          <td><div className="row" style={{ gap: 6 }}><code>{i.client_id}</code><CopyButton value={i.client_id} label=" " /></div></td>
                          <td><code className="faint">vss_••••{i.secret_hint}</code><div className="cell-sub">rotated {relTime(i.secret_rotated_at)}</div></td>
                          <td>{i.webhook_url ? <span className="badge b-outline">Webhook</span> : <span className="badge b-muted">Polling</span>}</td>
                          <td>{(i.submissions ?? 0).toLocaleString()}<div className="cell-sub">last token {relTime(i.last_used_at)}</div></td>
                          <td><StatusBadge status={i.status} /></td>
                          <td className="num">
                            <div className="row" style={{ justifyContent: "flex-end", gap: 4 }}>
                              <button className="btn btn-sm btn-ghost" title="Edit" onClick={() => setEditing(i)}><Pencil size={14} /></button>
                              <button className="btn btn-sm btn-ghost" title="Rotate secret" onClick={() => {
                                if (confirm(`Rotate the client secret for ${i.name}? The current secret and all tokens issued with it stop working immediately.`))
                                  void act(() => api.post<Integration>(`/api/admin/integrations/${i.id}/rotate-secret`), "New client secret");
                              }}><RefreshCw size={14} /></button>
                              {i.status === "active" ? (
                                <button className="btn btn-sm btn-ghost btn-danger" title="Revoke" onClick={() => {
                                  if (confirm(`Revoke ${i.name}? Its Complete calls will be rejected until reactivated.`))
                                    void act(() => api.post(`/api/admin/integrations/${i.id}/status?status=revoked`));
                                }}><Ban size={14} /></button>
                              ) : (
                                <button className="btn btn-sm btn-ghost" title="Reactivate" onClick={() => void act(() => api.post(`/api/admin/integrations/${i.id}/status?status=active`))}>
                                  <RotateCcw size={14} />
                                </button>
                              )}
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
            <QuickStart />
          </>
        )}
      </div>

      {creating && (
        <IntegrationForm
          onClose={() => setCreating(false)}
          onSaved={(i) => {
            setCreating(false);
            setRevealed({ title: "Integration created", integration: i });
            void reload();
          }}
        />
      )}
      {editing && (
        <IntegrationForm
          existing={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            void reload();
          }}
          onRotateWebhook={() => {
            setEditing(null);
            void act(() => api.post<Integration>(`/api/admin/integrations/${editing.id}/rotate-webhook-secret`), "New webhook signing secret");
          }}
        />
      )}
      {revealed && <RevealSecrets {...revealed} onClose={() => setRevealed(null)} />}
    </>
  );
}

function IntegrationForm({ existing, onClose, onSaved, onRotateWebhook }: {
  existing?: Integration; onClose: () => void; onSaved: (i: Integration) => void; onRotateWebhook?: () => void;
}) {
  const [name, setName] = useState(existing?.name ?? "");
  const [vendor, setVendor] = useState(existing?.vendor ?? "");
  const [webhook, setWebhook] = useState(existing?.webhook_url ?? "");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    setError(null);
    try {
      const body = { name, vendor, webhook_url: webhook || null };
      const saved = existing
        ? await api.patch<Integration>(`/api/admin/integrations/${existing.id}`, body)
        : await api.post<Integration>("/api/admin/integrations", body);
      onSaved(saved);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title={existing ? `Edit ${existing.name}` : "New integration"}
      onClose={onClose}
      footer={
        <>
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" disabled={busy || name.length < 2 || vendor.length < 2} onClick={() => void save()}>
            {existing ? "Save" : "Create and show credentials"}
          </button>
        </>
      }
    >
      <div className="stack">
        <ErrorAlert error={error} />
        <div className="field">
          <label>Name</label>
          <input className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder="Lab partner - Event 2026" />
        </div>
        <div className="field">
          <label>Vendor</label>
          <input className="input" value={vendor} onChange={(e) => setVendor(e.target.value)} placeholder="Lab partner name" />
        </div>
        <div className="field">
          <label>Results webhook URL (optional)</label>
          <input className="input" value={webhook} onChange={(e) => setWebhook(e.target.value)} placeholder="https://vendor.example.com/hooks/scoring" />
          <span className="hint">When set, every final result is POSTed here, signed with HMAC-SHA256 (header X-VectorSense-Signature).</span>
        </div>
        {existing && onRotateWebhook && (
          <button className="btn btn-sm" style={{ alignSelf: "flex-start" }} onClick={onRotateWebhook}>
            <Webhook size={14} /> Rotate webhook signing secret
          </button>
        )}
      </div>
    </Modal>
  );
}

function RevealSecrets({ title, integration, onClose }: Revealed & { onClose: () => void }) {
  return (
    <Modal title={title} onClose={onClose} footer={<button className="btn btn-primary" onClick={onClose}>I have stored these securely</button>}>
      <div className="stack">
        <div className="alert alert-warn">
          Copy these now. Secrets are stored hashed and cannot be shown again; rotate to issue a new one.
        </div>
        <SecretField label="Client ID" value={integration.client_id} />
        {integration.client_secret && <SecretField label="Client secret" value={integration.client_secret} />}
        {integration.webhook_secret && (
          <SecretField label="Webhook signing secret" value={integration.webhook_secret}
            hint="Used by the vendor to verify X-VectorSense-Signature on result callbacks." />
        )}
      </div>
    </Modal>
  );
}

function QuickStart() {
  const base = config().public_base_url.replace(/\/$/, "");
  const curl = `# 1. Handshake: exchange client credentials for a token (valid 60 minutes)
curl -s -X POST ${base}/oauth/token \\
  -d grant_type=client_credentials -d client_id=$CLIENT_ID -d client_secret=$CLIENT_SECRET

# 2. Participant clicked Complete
curl -s -X POST "${base}/v1/steps/complete?wait_seconds=10" \\
  -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: $(uuidgen)" -H "Content-Type: application/json" \\
  -d '{"event_id":"ignite-2026","use_case_id":"cowork-sales-brief","step_id":"step-1",
       "lab":{"lab_instance_id":"inst-1","lab_started_at":"2026-11-18T10:42:00Z"},
       "participant":{"external_id":"skl-55621","first_name":"Asha","last_name":"Kumar","email":"asha@contoso.com"},
       "lab_account":{"upn":"labuser0421@ignitetenant.onmicrosoft.com"}}'`;
  return (
    <details className="card">
      <summary className="card-head" style={{ cursor: "pointer", listStyle: "none", borderBottom: "none" }}>
        <div>
          <h3>Vendor quick start</h3>
          <div className="sub">Token: {base}/oauth/token · Complete: {base}/v1/steps/complete</div>
        </div>
        <span className="btn btn-sm">Show example</span>
      </summary>
      <div className="card-pad stack">
        <pre className="json">{curl}</pre>
        <div className="row">
          <CopyButton value={curl} label="Copy example" />
          <a className="btn btn-sm" href="/api/docs" target="_blank" rel="noreferrer">Open API reference</a>
        </div>
      </div>
    </details>
  );
}
