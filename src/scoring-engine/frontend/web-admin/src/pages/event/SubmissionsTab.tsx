import { useState } from "react";
import { Inbox } from "lucide-react";
import { Drawer, Empty, ErrorAlert, LiveIndicator, Loading, Search, StatusBadge, VerificationBadge } from "@shared/components/ui";
import { api } from "../../lib/api";
import { relTime } from "@shared/lib/format";
import { useLiveUpdates, useLoad } from "@shared/lib/hooks";
import type { EventDetail, SubmissionRow } from "@shared/lib/types";
import SubmissionDetail from "./SubmissionDetail";

const PAGE = 50;

export default function SubmissionsTab({ event }: { event: EventDetail }) {
  const [status, setStatus] = useState("");
  const [q, setQ] = useState("");
  const [term, setTerm] = useState("");
  const [page, setPage] = useState(0);
  const [open, setOpen] = useState<string | null>(null);
  const params = new URLSearchParams({ limit: String(PAGE), offset: String(page * PAGE) });
  if (status) params.set("status", status);
  if (term) params.set("q", term);
  const { data, error, reload } = useLoad(
    () => api.get<{ total: number; items: SubmissionRow[] }>(`/api/admin/events/${event.id}/submissions?${params}`),
    [event.id, status, term, page],
  );
  const live = useLiveUpdates(`/api/stream/events/${event.id}`, () => void reload());

  return (
    <div className="card">
      <div className="toolbar">
        <form onSubmit={(e) => { e.preventDefault(); setPage(0); setTerm(q); }}>
          <Search value={q} onChange={setQ} placeholder="Search name, UPN or participant ID, then Enter" width={340} />
        </form>
        <select className="select" value={status} onChange={(e) => { setPage(0); setStatus(e.target.value); }}>
          <option value="">All Results</option>
          <option value="complete">Complete</option>
          <option value="incomplete">Incomplete</option>
          <option value="evaluating">Evaluating</option>
          <option value="error">Error</option>
        </select>
        <LiveIndicator {...live} />
      </div>
      <ErrorAlert error={error} />
      {!data ? <Loading /> : data.items.length === 0 ? (
        <Empty icon={<Inbox size={22} />} title="No submissions match">Complete clicks from lab vendors show up here in real time.</Empty>
      ) : (
        <>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>Participant</th><th>Step</th><th>Result</th><th>Reason</th><th className="num">Passes</th><th className="num">Received</th></tr>
              </thead>
              <tbody>
                {data.items.map((s) => (
                  <tr key={s.id} className="clickable" onClick={() => setOpen(s.id)}>
                    <td><div style={{ fontWeight: 500 }}>{s.participant}</div><div className="cell-sub">{s.upn}</div></td>
                    <td>{s.step_title}<div className="cell-sub mono">{s.use_case}/{s.step}</div></td>
                    <td><div className="row wrap"><StatusBadge status={s.status} /><VerificationBadge status={s.verification_status} />
                      {s.source === "sync" && <span className="badge b-outline" title="Found by Microsoft 365 sync">Sync</span>}</div></td>
                    <td className="small muted" style={{ maxWidth: 380 }}>{s.reasons.map((r) => r.message).join(" ")}</td>
                    <td className="num">{s.attempts}</td>
                    <td className="num faint small">{relTime(s.received_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="table-foot">
            <span>Showing <b>{page * PAGE + 1}–{Math.min((page + 1) * PAGE, data.total)}</b> of <b>{data.total.toLocaleString()}</b></span>
            <div className="row">
              <button className="btn btn-sm" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</button>
              <button className="btn btn-sm" disabled={(page + 1) * PAGE >= data.total} onClick={() => setPage(page + 1)}>Next</button>
            </div>
          </div>
        </>
      )}
      {open && (
        <Drawer onClose={() => setOpen(null)}>
          <SubmissionDetail id={open} onClose={() => setOpen(null)} onChanged={() => void reload()} />
        </Drawer>
      )}
    </div>
  );
}
