import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Save, Trash2, Upload, Users } from "lucide-react";
import { CopyButton, ErrorAlert } from "@shared/components/ui";
import { config } from "@shared/lib/config";
import { fromLocalInput, toLocalInput } from "@shared/lib/format";
import type { EventDetail } from "@shared/lib/types";
import { api, ApiError } from "../../lib/api";

const ROSTER_TEMPLATE = `upn,first_name,last_name,email,external_id,lab_started_at
labuser0001@yourlabtenant.onmicrosoft.com,Asha,Kumar,asha.kumar@contoso.com,,2026-11-18T10:00:00Z`;

export default function SettingsTab({ event, reload }: { event: EventDetail; reload: () => Promise<void> }) {
  const nav = useNavigate();
  const [form, setForm] = useState({
    name: event.name,
    description: event.description ?? "",
    status: event.status,
    starts_at: toLocalInput(event.starts_at),
    ends_at: toLocalInput(event.ends_at),
    public_leaderboard: event.public_leaderboard,
    public_show_reasons: event.public_show_reasons,
    roster_group_id: event.roster_group_id ?? "",
  });
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) => { setForm({ ...form, [k]: v }); setSaved(false); };
  const scorecardUrl = `${config().scorecard_base_url.replace(/\/$/, "")}/${event.slug}`;

  async function save() {
    setError(null);
    try {
      await api.patch(`/api/admin/events/${event.id}`, {
        ...form, description: form.description || null, roster_group_id: form.roster_group_id.trim() || null,
        starts_at: fromLocalInput(form.starts_at), ends_at: fromLocalInput(form.ends_at),
      });
      setSaved(true);
      await reload();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : String(e));
    }
  }

  return (
    <div className="grid grid-2" style={{ alignItems: "start" }}>
      <div className="stack">
        <div className="card card-pad stack">
          <h3>Event</h3>
          <ErrorAlert error={error} />
          {saved && <div className="alert alert-ok">Saved.</div>}
          <div className="field"><label>Name</label><input className="input" value={form.name} onChange={(e) => set("name", e.target.value)} /></div>
          <div className="field"><label>Description (shown on the participant scorecard)</label>
            <textarea className="textarea" rows={3} value={form.description} onChange={(e) => set("description", e.target.value)} /></div>
          <div className="field">
            <label>Status</label>
            <select className="select" value={form.status} onChange={(e) => set("status", e.target.value as typeof form.status)}>
              <option value="draft">Draft: accepting test calls, scorecards hidden</option>
              <option value="live">Live: accepting Complete calls and syncs</option>
              <option value="closed">Closed: Complete calls rejected (409)</option>
            </select>
          </div>
          <div className="grid grid-2">
            <div className="field"><label>Starts</label><input type="datetime-local" className="input" value={form.starts_at} onChange={(e) => set("starts_at", e.target.value)} />
              <span className="hint">Also the evidence start for lab accounts without their own lab start time.</span></div>
            <div className="field"><label>Ends</label><input type="datetime-local" className="input" value={form.ends_at} onChange={(e) => set("ends_at", e.target.value)} /></div>
          </div>
          <div><button className="btn btn-primary" onClick={() => void save()}><Save size={15} /> Save settings</button></div>
        </div>

        <div className="card card-pad stack">
          <h3>Participant scorecard</h3>
          <label className="check"><input type="checkbox" checked={form.public_leaderboard} onChange={(e) => set("public_leaderboard", e.target.checked)} /> Participants can look up their own scorecard with their lab account</label>
          <label className="check"><input type="checkbox" checked={form.public_show_reasons} onChange={(e) => set("public_show_reasons", e.target.checked)} /> Show participants why a step is incomplete</label>
          <div className="alert alert-info">Participants only ever see their own results. The full leaderboard is visible to administrators only.</div>
          <div className="field">
            <label>Scorecard URL</label>
            <div className="row"><code className="grow">{scorecardUrl}</code><CopyButton value={scorecardUrl} /></div>
          </div>
          <div><button className="btn btn-primary" onClick={() => void save()}><Save size={15} /> Save settings</button></div>
        </div>
      </div>

      <div className="stack">
        <RosterCard event={event} groupId={form.roster_group_id} onGroupChange={(v) => set("roster_group_id", v)} onSave={save} reload={reload} />
        <div className="card card-pad stack">
          <h3>Danger zone</h3>
          <div className="muted small">Deleting the event removes all use cases, participants, submissions and leaderboard data.</div>
          <div>
            <button className="btn btn-danger" onClick={async () => {
              if (prompt(`Type ${event.slug} to delete this event permanently`) !== event.slug) return;
              await api.del(`/api/admin/events/${event.id}`);
              nav("/events");
            }}><Trash2 size={15} /> Delete event</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function RosterCard({ event, groupId, onGroupChange, onSave, reload }: {
  event: EventDetail; groupId: string; onGroupChange: (v: string) => void; onSave: () => Promise<void>; reload: () => Promise<void>;
}) {
  const [csv, setCsv] = useState("");
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function importCsv() {
    setError(null);
    setResult(null);
    try {
      const r = await api.post<{ added: number; updated: number; rows: number }>(`/api/admin/events/${event.id}/roster`, { csv });
      setResult(`Imported ${r.rows} lab accounts: ${r.added} added, ${r.updated} updated.`);
      setCsv("");
      await reload();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : String(e));
    }
  }

  return (
    <div className="card card-pad stack">
      <h3 className="row"><Users size={16} className="faint" /> Lab account roster</h3>
      <div className="muted small">
        Microsoft 365 sync scores every lab account on the roster. Accounts are added automatically when the lab platform calls the API,
        and can also come from an Entra group or a CSV import.
      </div>
      <div className="field">
        <label>Entra group with the event's lab accounts</label>
        <div className="row">
          <input className="input mono" placeholder="Group object ID" value={groupId} onChange={(e) => onGroupChange(e.target.value)} />
          <button className="btn" onClick={() => void onSave()}><Save size={15} /> Save</button>
        </div>
        <span className="hint">Members are picked up at the start of every sync. Requires GroupMember.Read.All.</span>
      </div>
      <div className="field">
        <label>Import from CSV</label>
        <textarea className="textarea mono" rows={5} placeholder={ROSTER_TEMPLATE} value={csv} onChange={(e) => setCsv(e.target.value)} />
        <span className="hint">Header row required. Only <code>upn</code> is mandatory; <code>lab_started_at</code> (ISO-8601) sets that account's evidence start.</span>
      </div>
      <ErrorAlert error={error} />
      {result && <div className="alert alert-ok">{result}</div>}
      <div className="row">
        <button className="btn btn-primary" disabled={csv.trim().length < 5} onClick={() => void importCsv()}><Upload size={15} /> Import roster</button>
        <button className="btn btn-ghost" onClick={() => setCsv(ROSTER_TEMPLATE)}>Use template</button>
      </div>
    </div>
  );
}
