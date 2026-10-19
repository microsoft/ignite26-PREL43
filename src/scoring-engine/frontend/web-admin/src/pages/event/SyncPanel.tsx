import { useEffect, useRef, useState } from "react";
import { CloudDownload, Loader2, RefreshCw } from "lucide-react";
import { ErrorAlert, StatusBadge } from "@shared/components/ui";
import { dateTime, duration, relTime } from "@shared/lib/format";
import { useLoad } from "@shared/lib/hooks";
import { api } from "../../lib/api";

interface SyncRun {
  id: string;
  status: "queued" | "running" | "completed" | "completed_with_errors" | "failed";
  triggered_by: string;
  watermark_from: string | null;
  watermark_to: string | null;
  participants_total: number;
  participants_scanned: number;
  participants_added: number;
  steps_checked: number;
  steps_skipped: number;
  new_completions: number;
  errors: number;
  error_detail: string | null;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
}

const RUN_BADGE: Record<SyncRun["status"], string> = {
  queued: "pending", running: "evaluating", completed: "complete", completed_with_errors: "error", failed: "failed",
};

/**
 * Organiser-initiated sync: scores every lab account straight from Microsoft 365. Works whether or not the
 * lab platform calls the API, and only re-checks steps that are not complete yet.
 */
export default function SyncPanel({ eventId, onFinished, tick }: { eventId: string; onFinished: () => void; tick: number }) {
  const { data, reload } = useLoad(
    () => api.get<{ last_synced_at: string | null; runs: SyncRun[] }>(`/api/admin/events/${eventId}/sync-runs`), [eventId]);
  const [error, setError] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);
  const active = data?.runs.find((r) => r.status === "queued" || r.status === "running");
  const wasActive = useRef(false);

  useEffect(() => { void reload(); }, [tick, reload]);
  useEffect(() => {
    if (!active) return;
    const t = window.setInterval(() => void reload(), 2000);
    return () => window.clearInterval(t);
  }, [active, reload]);
  useEffect(() => {
    if (wasActive.current && !active) onFinished();
    wasActive.current = !!active;
  }, [active, onFinished]);

  async function start() {
    setError(null);
    setStarting(true);
    try {
      await api.post(`/api/admin/events/${eventId}/sync`);
      await reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setStarting(false);
    }
  }

  const last = data?.runs.find((r) => r.status !== "queued" && r.status !== "running");
  const pct = active && active.participants_total ? (active.participants_scanned / active.participants_total) * 100 : 0;

  return (
    <div className="card">
      <div className="panel-head">
        <div>
          <h3><CloudDownload size={16} className="faint" /> Microsoft 365 sync</h3>
          <div className="sub">Scores every lab account directly from Microsoft 365. Only steps that are not complete yet are re-checked.</div>
        </div>
        <button className="btn btn-primary" disabled={!!active || starting} onClick={() => void start()}>
          {active || starting ? <Loader2 size={15} className="spin" /> : <RefreshCw size={15} />}
          {active ? "Syncing…" : "Sync now"}
        </button>
      </div>
      <ErrorAlert error={error} />
      <div className="grid grid-3" style={{ padding: "16px 20px", gap: 12 }}>
        <div>
          <div className="faint small">Last synced</div>
          <div style={{ fontWeight: 600, fontSize: 15 }}>{data?.last_synced_at ? relTime(data.last_synced_at) : "Never"}</div>
          <div className="cell-sub">{data?.last_synced_at ? `Evidence scanned up to ${dateTime(data.last_synced_at)}` : "Run a sync to score from Microsoft 365"}</div>
        </div>
        <div>
          <div className="faint small">{active ? "Current run" : "Last run"}</div>
          {active ? (
            <>
              <div style={{ fontWeight: 600, fontSize: 15 }}>{active.participants_scanned} of {active.participants_total || "…"} lab accounts</div>
              <div className="progress" style={{ marginTop: 6 }}><span style={{ width: `${pct}%` }} /></div>
            </>
          ) : last ? (
            <>
              <div style={{ fontWeight: 600, fontSize: 15 }}>{last.new_completions} new completion{last.new_completions === 1 ? "" : "s"}</div>
              <div className="cell-sub">{last.steps_checked} checked · {last.steps_skipped} already complete · {last.errors} errors</div>
            </>
          ) : <div className="cell-sub">No runs yet</div>}
        </div>
        <div>
          <div className="faint small">Roster</div>
          <div style={{ fontWeight: 600, fontSize: 15 }}>{last ? `${last.participants_total} lab accounts` : "—"}</div>
          <div className="cell-sub">From partner calls, an imported roster, or the event's Entra group (Settings)</div>
        </div>
      </div>
      {data && data.runs.length > 0 && (
        <table className="plain">
          <thead>
            <tr>
              <th>Run</th><th>Window scanned</th><th className="num">Accounts</th><th className="num">Checked</th>
              <th className="num">Skipped</th><th className="num">Completions</th><th className="num">Errors</th><th>Status</th>
            </tr>
          </thead>
          <tbody>
            {data.runs.slice(0, 5).map((r) => (
              <tr key={r.id} title={r.error_detail ?? ""}>
                <td>{dateTime(r.created_at)}<div className="cell-sub">by {r.triggered_by}{r.finished_at && r.started_at
                  ? ` · ${duration(Math.round((new Date(r.finished_at).getTime() - new Date(r.started_at).getTime()) / 1000))}` : ""}</div></td>
                <td className="small">{r.watermark_from ? dateTime(r.watermark_from) : "Lab start"} <span className="faint">→</span> {r.watermark_to ? dateTime(r.watermark_to) : "…"}</td>
                <td className="num">{r.participants_total}{r.participants_added ? <div className="cell-sub">+{r.participants_added} new</div> : null}</td>
                <td className="num">{r.steps_checked}</td>
                <td className="num faint">{r.steps_skipped}</td>
                <td className="num" style={{ fontWeight: 600 }}>{r.new_completions}</td>
                <td className="num">{r.errors}</td>
                <td><StatusBadge status={RUN_BADGE[r.status]} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
