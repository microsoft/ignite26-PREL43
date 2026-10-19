import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Activity, CalendarRange, ExternalLink, Plus, Radio, Users } from "lucide-react";
import { PageHeader } from "../components/Layout";
import { Empty, ErrorAlert, Loading, Modal, Search, Stat, StatusBadge } from "@shared/components/ui";
import { api, ApiError } from "../lib/api";
import { config } from "@shared/lib/config";
import { dateTime, fromLocalInput } from "@shared/lib/format";
import { useLoad } from "@shared/lib/hooks";
import type { EventSummary } from "@shared/lib/types";

export default function Events() {
  const { data, error, reload } = useLoad(() => api.get<EventSummary[]>("/api/admin/events"));
  const [creating, setCreating] = useState(false);
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("");
  const nav = useNavigate();

  const rows = useMemo(() => (data ?? []).filter((e) =>
    (!status || e.status === status) &&
    (!q || `${e.name} ${e.slug}`.toLowerCase().includes(q.toLowerCase()))), [data, q, status]);
  const sum = (k: "participants" | "submissions") => (data ?? []).reduce((n, e) => n + (e[k] ?? 0), 0);

  return (
    <>
      <PageHeader
        crumbs={[{ label: "Events" }]}
        title="Events"
        sub="Each event holds use cases, steps and the evidence rubric that decides every step."
        actions={<button className="btn btn-primary" onClick={() => setCreating(true)}><Plus size={16} /> New Event</button>}
      />
      <ErrorAlert error={error} />
      {!data ? <Loading /> : (
        <>
          <div className="grid grid-4">
            <Stat tone="blue" icon={<CalendarRange size={16} />} value={data.length} label="All Events" foot={`${data.filter((e) => e.status === "draft").length} in draft`} />
            <Stat tone="orange" icon={<Radio size={16} />} value={data.filter((e) => e.status === "live").length} label="Live Events" foot="Accepting Complete calls" />
            <Stat tone="purple" icon={<Users size={16} />} value={sum("participants").toLocaleString()} label="Participants" foot="Across all events" />
            <Stat tone="pink" icon={<Activity size={16} />} value={sum("submissions").toLocaleString()} label="Submissions" foot="Complete clicks evaluated" />
          </div>

          <div className="card mt">
            <div className="toolbar">
              <Search value={q} onChange={setQ} placeholder="Search events by name or event_id…" />
              <select className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
                <option value="">All Statuses</option>
                <option value="live">Live</option>
                <option value="draft">Draft</option>
                <option value="closed">Closed</option>
              </select>
            </div>
            {data.length === 0 ? (
              <Empty icon={<CalendarRange size={20} />} title="No events yet">Create the event the lab vendor will reference as event_id.</Empty>
            ) : (
              <>
                <div className="table-wrap">
                  <table className="table">
                    <thead>
                      <tr>
                        <th>Event ID</th><th>Event</th><th>Window</th><th>Participants</th><th>Submissions</th><th>Scorecard</th><th>Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((e) => (
                        <tr key={e.id} className="clickable" onClick={() => nav(`/events/${e.id}`)}>
                          <td className="mono">{e.slug}</td>
                          <td><div style={{ fontWeight: 500 }}>{e.name}</div><div className="cell-sub">{e.description}</div></td>
                          <td className="small muted">{e.starts_at ? <>{dateTime(e.starts_at)}<div className="cell-sub">to {dateTime(e.ends_at)}</div></> : "—"}</td>
                          <td>{e.participants}<div className="cell-sub">Participants</div></td>
                          <td>{e.submissions}<div className="cell-sub">Clicks</div></td>
                          <td onClick={(ev) => ev.stopPropagation()}>
                            {e.public_leaderboard && e.status !== "draft"
                              ? <a href={`${config().scorecard_base_url}/${e.slug}`} target="_blank" rel="noreferrer" className="row small" style={{ gap: 5 }}>/{e.slug} <ExternalLink size={12} /></a>
                              : <span className="faint small">{e.public_leaderboard ? "Opens when live" : "Off"}</span>}
                          </td>
                          <td><StatusBadge status={e.status} /></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div className="table-foot"><span>Showing <b>{rows.length}</b> of <b>{data.length}</b></span></div>
              </>
            )}
          </div>
        </>
      )}
      {creating && <CreateEvent onClose={() => setCreating(false)} onCreated={(id) => { void reload(); nav(`/events/${id}`); }} />}
    </>
  );
}

function CreateEvent({ onClose, onCreated }: { onClose: () => void; onCreated: (id: string) => void }) {
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [touchedSlug, setTouchedSlug] = useState(false);
  const [description, setDescription] = useState("");
  const [starts, setStarts] = useState("");
  const [ends, setEnds] = useState("");
  const [error, setError] = useState<string | null>(null);

  const autoSlug = (v: string) => v.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60);

  async function save() {
    setError(null);
    try {
      const e = await api.post<EventSummary>("/api/admin/events", {
        name, slug, description: description || null, starts_at: fromLocalInput(starts), ends_at: fromLocalInput(ends),
      });
      onCreated(e.id);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : String(err));
    }
  }

  return (
    <Modal title="New event" onClose={onClose} footer={
      <>
        <button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" disabled={name.length < 2 || slug.length < 2} onClick={() => void save()}>Create event</button>
      </>
    }>
      <div className="stack">
        <ErrorAlert error={error} />
        <div className="field">
          <label>Event name</label>
          <input className="input" value={name} autoFocus onChange={(e) => { setName(e.target.value); if (!touchedSlug) setSlug(autoSlug(e.target.value)); }}
            placeholder="Microsoft Ignite 2026 - Cowork Challenge" />
        </div>
        <div className="field">
          <label>Event ID</label>
          <input className="input mono" value={slug} onChange={(e) => { setTouchedSlug(true); setSlug(e.target.value); }} />
          <span className="hint">Lab partners send this as event_id. Participant scorecard: /{slug || "…"}</span>
        </div>
        <div className="field">
          <label>Description</label>
          <textarea className="textarea" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
        </div>
        <div className="grid grid-2">
          <div className="field"><label>Starts</label><input type="datetime-local" className="input" value={starts} onChange={(e) => setStarts(e.target.value)} /></div>
          <div className="field"><label>Ends</label><input type="datetime-local" className="input" value={ends} onChange={(e) => setEnds(e.target.value)} /></div>
        </div>
      </div>
    </Modal>
  );
}
