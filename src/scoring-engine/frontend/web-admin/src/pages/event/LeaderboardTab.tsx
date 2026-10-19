import { useEffect, useMemo, useRef, useState } from "react";
import { CheckCircle2, Download, FileSpreadsheet, ListChecks, Trophy, Users } from "lucide-react";
import { Empty, ErrorAlert, LiveIndicator, Loading, Search, Stat, StepCell, VerificationBadge } from "@shared/components/ui";
import { api, download } from "../../lib/api";
import { duration, initials, relTime, stepLabels } from "@shared/lib/format";
import { useLiveUpdates, useLoad } from "@shared/lib/hooks";
import type { Board, EventDetail } from "@shared/lib/types";
import ParticipantDrawer from "./ParticipantDrawer";
import SyncPanel from "./SyncPanel";

export default function LeaderboardTab({ event }: { event: EventDetail }) {
  const { data, error, reload } = useLoad(() => api.get<Board>(`/api/admin/events/${event.id}/leaderboard`), [event.id]);
  const [tick, setTick] = useState(0);
  const live = useLiveUpdates(`/api/stream/events/${event.id}`, () => { void reload(); setTick((t) => t + 1); });
  const [q, setQ] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const flashes = useFlashes(data);

  const rows = useMemo(() => {
    if (!data) return [];
    const term = q.trim().toLowerCase();
    if (!term) return data.rows;
    return data.rows.filter((r) => [r.name, r.email, r.upn, r.external_id].some((v) => (v ?? "").toLowerCase().includes(term)));
  }, [data, q]);

  async function exportAs(format: "csv" | "xlsx") {
    setBusy(format);
    try {
      await download(`/api/admin/events/${event.id}/leaderboard/export?format=${format}`);
    } finally {
      setBusy(null);
    }
  }

  if (!data) return <><ErrorAlert error={error} />{!error && <Loading />}</>;
  const labels = stepLabels(data.steps);
  const completions = data.steps.reduce((n, s) => n + s.completed_count, 0);
  const possible = data.participants_total * data.steps.length;

  return (
    <div className="stack">
      <div className="grid grid-4">
        <Stat tone="blue" icon={<Users size={16} />} value={data.participants_total} label="Participants" foot="On the board" />
        <Stat tone="orange" icon={<Trophy size={16} />} value={data.finished_total} label="Finished All Steps"
          foot={`${data.participants_total ? Math.round((data.finished_total / data.participants_total) * 100) : 0}% of participants`} />
        <Stat tone="purple" icon={<CheckCircle2 size={16} />} value={completions} label="Steps Completed"
          foot={`${possible ? Math.round((completions / possible) * 100) : 0}% of all possible`} />
        <Stat tone="pink" icon={<ListChecks size={16} />} value={data.steps.length} label="Steps in Event" foot={`${new Set(data.steps.map((s) => s.use_case_code)).size} use cases`} />
      </div>

      <SyncPanel eventId={event.id} tick={tick} onFinished={() => void reload()} />

      <div className="card">
        <div className="panel-head">
          <div>
            <h3>Completion by step</h3>
            <div className="sub">Participants who completed each step</div>
          </div>
        </div>
        <div className="card-pad step-bars">
          {data.steps.map((s) => {
            const pct = data.participants_total ? (s.completed_count / data.participants_total) * 100 : 0;
            return (
              <div key={s.id} className="step-bar" title={`${s.use_case}: ${s.title}`}>
                <span className="lbl">{labels[s.id]}</span>
                <span className="ttl">{s.title} <span className="faint">· {s.use_case}</span></span>
                <div className="progress"><span style={{ width: `${pct}%` }} /></div>
                <span className="n">{s.completed_count}</span>
              </div>
            );
          })}
        </div>
      </div>

      <div className="card">
        <div className="toolbar">
          <Search value={q} onChange={setQ} placeholder="Search name, email, UPN or participant ID…" />
          <LiveIndicator {...live} />
          <span className="grow" />
          <button className="btn" disabled={!!busy} onClick={() => void exportAs("csv")}><Download size={15} /> Export CSV</button>
          <button className="btn" disabled={!!busy} onClick={() => void exportAs("xlsx")}><FileSpreadsheet size={15} /> Export Excel</button>
        </div>
        {data.rows.length === 0 ? (
          <Empty icon={<Trophy size={20} />} title="Nobody on the board yet">Participants appear when their lab vendor sends the first Complete click.</Empty>
        ) : (
          <>
            <div className="table-wrap">
              <table className="table">
                <thead>
                  <tr>
                    <th style={{ width: 64 }}>Rank</th>
                    <th>Participant</th>
                    <th>Progress</th>
                    {data.steps.map((s) => <th key={s.id} className="center" title={`${s.use_case}: ${s.title}`}>{labels[s.id]}</th>)}
                    <th className="num">Time</th>
                    <th className="num">Attempts</th>
                    <th className="num">Last</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.public_id} className={`clickable ${flashes.has(r.public_id) ? "flash" : ""}`} onClick={() => setSelected(r.participant_id ?? null)}>
                      <td>{r.rank ? <span className={`rank rank-${r.rank}`}>{r.rank}</span> : <span className="faint">—</span>}</td>
                      <td>
                        <div className="row">
                          <span className="avatar">{initials(r.name)}</span>
                          <div><div style={{ fontWeight: 500 }}>{r.name}</div><div className="cell-sub">{r.upn}</div></div>
                        </div>
                      </td>
                      <td style={{ minWidth: 150 }}>
                        <div className="row small">
                          <div className="progress grow"><span style={{ width: `${(r.completed_steps / Math.max(r.total_steps, 1)) * 100}%` }} /></div>
                          <span style={{ fontWeight: 600 }}>{r.completed_steps}/{r.total_steps}</span>
                        </div>
                      </td>
                      {data.steps.map((s) => (
                        <td key={s.id} className="center">
                          <StepCell state={r.steps[s.id]} title={`${s.title}: ${r.steps[s.id]}${r.verification[s.id] && r.verification[s.id] !== "not_required" ? ` (${r.verification[s.id]})` : ""}`} />
                          {r.verification[s.id] === "unverified" && <div style={{ marginTop: 2 }}><VerificationBadge status="unverified" /></div>}
                        </td>
                      ))}
                      <td className="num">{duration(r.elapsed_seconds)}</td>
                      <td className="num">{r.attempts}</td>
                      <td className="num faint small">{relTime(r.last_completed_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="table-foot">
              <span>Showing <b>{rows.length}</b> of <b>{data.rows.length}</b> · ranked by steps completed, then fastest time from lab start</span>
              <span className="faint small">{data.steps.map((s) => `${labels[s.id]} ${s.title}`).join(" · ")}</span>
            </div>
          </>
        )}
      </div>
      {selected && <ParticipantDrawer eventId={event.id} participantId={selected} onClose={() => setSelected(null)} />}
    </div>
  );
}

/** Highlights rows whose completed count changed since the last refresh. */
export function useFlashes(board: Board | null): Set<string> {
  const prev = useRef<Map<string, number>>(new Map());
  const [flash, setFlash] = useState<Set<string>>(new Set());
  useEffect(() => {
    if (!board) return;
    const changed = new Set<string>();
    for (const r of board.rows) {
      const before = prev.current.get(r.public_id);
      if (before !== undefined && before !== r.completed_steps + r.attempts) changed.add(r.public_id);
      prev.current.set(r.public_id, r.completed_steps + r.attempts);
    }
    if (changed.size) {
      setFlash(changed);
      const t = window.setTimeout(() => setFlash(new Set()), 1700);
      return () => window.clearTimeout(t);
    }
  }, [board]);
  return flash;
}
