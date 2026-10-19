import { useState } from "react";
import { RotateCcw, ShieldCheck, ShieldX, X } from "lucide-react";
import { CheckIcon, ErrorAlert, Loading, StatusBadge, VerificationBadge } from "@shared/components/ui";
import { api } from "../../lib/api";
import { dateTime } from "@shared/lib/format";
import { useLoad } from "@shared/lib/hooks";
import type { SubmissionDetail as Detail } from "@shared/lib/types";

export default function SubmissionDetail({ id, onClose, onChanged }: { id: string; onClose: () => void; onChanged?: () => void }) {
  const { data, error, reload } = useLoad(() => api.get<Detail>(`/api/admin/submissions/${id}`), [id]);
  const [override, setOverride] = useState<"complete" | "incomplete" | null>(null);
  const [note, setNote] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);
  const [showRaw, setShowRaw] = useState(false);

  async function run(fn: () => Promise<unknown>) {
    setActionError(null);
    try {
      await fn();
      await reload();
      onChanged?.();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : String(e));
    }
  }

  return (
    <>
      <div className="modal-head">
        <div>
          <h3>Submission</h3>
          <div className="faint small mono">{id}</div>
        </div>
        <button className="btn btn-ghost icon-btn" onClick={onClose} aria-label="Close"><X size={18} /></button>
      </div>
      <div className="modal-body stack">
        <ErrorAlert error={error ?? actionError} />
        {!data ? <Loading /> : (
          <>
            <div className="row wrap">
              <StatusBadge status={data.status} />
              <VerificationBadge status={data.verification_status} />
              {data.override_by && <span className="badge b-brand">Overridden by {data.override_by}</span>}
            </div>
            <dl className="kv">
              <dt>Participant</dt><dd><b>{data.participant}</b> <span className="faint">({data.external_id})</span></dd>
              <dt>Lab account</dt><dd><code>{data.upn}</code></dd>
              <dt>Step</dt><dd>{data.step_title} <span className="faint mono small">{data.use_case}/{data.step} · rubric v{data.rubric_version}</span></dd>
              <dt>Lab started</dt><dd>{dateTime(data.lab_started_at)}</dd>
              <dt>Clicked Complete</dt><dd>{dateTime(data.received_at)}</dd>
              <dt>Evaluated</dt><dd>{dateTime(data.evaluated_at)} · {data.attempts} evaluation pass(es)</dd>
              <dt>Lab instance</dt><dd className="mono small">{data.lab_profile_id ?? "—"} / {data.lab_instance_id ?? "—"}</dd>
              {data.override_note && (<><dt>Override note</dt><dd>{data.override_note}</dd></>)}
            </dl>

            <h4 className="mt">Evidence checks</h4>
            {data.check_results.length === 0 && <div className="faint">Not evaluated yet.</div>}
            {data.check_results.map((c) => (
              <div key={c.id} className={`check-item ${c.status}`}>
                <span className="ci-icon"><CheckIcon status={c.status} /></span>
                <div className="grow" style={{ minWidth: 0 }}>
                  <div className="row-between">
                    <b>{c.description || c.id}</b>
                    <span className="row">
                      {c.mode === "deferred" && <span className="badge b-muted" title="Re-verified in the background; never blocks the participant">deferred</span>}
                      <code className="faint">{c.type}</code>
                    </span>
                  </div>
                  <div className="small muted" style={{ marginTop: 2 }}>{c.message}</div>
                  {Object.keys(c.evidence ?? {}).length > 0 && (
                    <details className="small" style={{ marginTop: 6 }}>
                      <summary className="faint" style={{ cursor: "pointer" }}>Evidence</summary>
                      <pre className="json" style={{ marginTop: 6 }}>{JSON.stringify(c.evidence, null, 2)}</pre>
                    </details>
                  )}
                </div>
              </div>
            ))}

            <h4 className="mt">Actions</h4>
            <div className="row wrap">
              <button className="btn btn-sm" onClick={() => void run(() => api.post(`/api/admin/submissions/${id}/reevaluate`))}>
                <RotateCcw size={14} /> Re-evaluate now
              </button>
              <button className="btn btn-sm" onClick={() => setOverride("complete")}><ShieldCheck size={14} /> Mark complete</button>
              <button className="btn btn-sm btn-danger" onClick={() => setOverride("incomplete")}><ShieldX size={14} /> Mark incomplete</button>
              <button className="btn btn-sm btn-ghost" onClick={() => setShowRaw((v) => !v)}>{showRaw ? "Hide" : "Show"} vendor response</button>
            </div>
            {override && (
              <div className="card card-pad stack">
                <div className="field">
                  <label>Reason for marking {override} (audited{override === "incomplete" ? ", shown to the participant" : ""})</label>
                  <textarea className="textarea" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
                </div>
                <div className="row">
                  <button className="btn btn-primary btn-sm" disabled={note.length < 3}
                    onClick={() => void run(async () => {
                      await api.post(`/api/admin/submissions/${id}/override`, { status: override, note });
                      setOverride(null);
                      setNote("");
                    })}>Apply override</button>
                  <button className="btn btn-sm" onClick={() => setOverride(null)}>Cancel</button>
                </div>
              </div>
            )}
            {showRaw && <pre className="json">{JSON.stringify(data.vendor_view, null, 2)}</pre>}
          </>
        )}
      </div>
    </>
  );
}
