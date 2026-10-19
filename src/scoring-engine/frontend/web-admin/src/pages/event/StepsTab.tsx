import { useState } from "react";
import { CheckCircle2, FileCode2, ListChecks, Pencil, Plus, Trash2 } from "lucide-react";
import { Empty, ErrorAlert, Modal } from "@shared/components/ui";
import { api, ApiError } from "../../lib/api";
import { relTime } from "@shared/lib/format";
import { useLoad } from "@shared/lib/hooks";
import type { CheckType, EventDetail, StepDef, UseCaseDef } from "@shared/lib/types";

const STARTER = `checks:
  - id: output_file
    type: onedrive_file
    description: Output saved by Cowork
    params:
      folder: /Cowork
      name_pattern: "*"
      extensions: [docx]
      content_contains: []
    retry_window_seconds: 45
    fail_message: We could not find the expected document in your OneDrive Cowork folder.
`;

export default function StepsTab({ event, reload }: { event: EventDetail; reload: () => Promise<void> }) {
  const [ucForm, setUcForm] = useState<UseCaseDef | "new" | null>(null);
  const [stepForm, setStepForm] = useState<{ uc: UseCaseDef; step?: StepDef } | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function remove(path: string, what: string) {
    if (!confirm(`Delete ${what}? Its submissions and leaderboard progress are deleted too.`)) return;
    try {
      await api.del(path);
      await reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  return (
    <div className="stack">
      <ErrorAlert error={error} />
      <div className="alert alert-info">
        Vendors reference steps by <code>use_case_id</code> and <code>step_id</code>. Each step has a YAML rubric of evidence
        checks; the step is complete only when every blocking check passes. Editing a rubric creates a new version.
      </div>
      {event.use_cases.length === 0 && (
        <div className="card"><Empty icon={<ListChecks size={22} />} title="No use cases yet">Add the first use case, then its steps.</Empty></div>
      )}
      {event.use_cases.map((uc) => (
        <div className="card" key={uc.id}>
          <div className="panel-head">
            <div>
              <h3>{uc.title}</h3>
              <div className="sub">use_case_id <code>{uc.code}</code>{uc.description ? ` · ${uc.description}` : ""}</div>
            </div>
            <div className="row">
              <button className="btn btn-sm" onClick={() => setUcForm(uc)}><Pencil size={14} /> Edit</button>
              <button className="btn btn-sm btn-ghost btn-danger" onClick={() => void remove(`/api/admin/use-cases/${uc.id}`, `use case ${uc.code}`)}><Trash2 size={14} /></button>
              <button className="btn btn-sm btn-primary" onClick={() => setStepForm({ uc })}><Plus size={14} /> Step</button>
            </div>
          </div>
          <table className="plain">
            <thead><tr><th>step_id</th><th>Step</th><th>Checks</th><th>Rubric</th><th className="num">Updated</th><th /></tr></thead>
            <tbody>
              {uc.steps.length === 0 && <tr><td colSpan={6} className="faint">No steps yet.</td></tr>}
              {uc.steps.map((s) => (
                <tr key={s.id} className="clickable" onClick={() => setStepForm({ uc, step: s })}>
                  <td><code>{s.code}</code></td>
                  <td><b>{s.title}</b>{s.description && <div className="faint small">{s.description}</div>}</td>
                  <td>{s.check_count ? <span className="badge b-ok"><CheckCircle2 size={12} /> {s.check_count} checks</span> : <span className="badge b-warn">No rubric</span>}</td>
                  <td className="faint small">v{s.rubric_version}</td>
                  <td className="num faint small">{relTime(s.updated_at)}</td>
                  <td className="num" onClick={(e) => e.stopPropagation()}>
                    <button className="btn btn-sm btn-ghost btn-danger" onClick={() => void remove(`/api/admin/steps/${s.id}`, `step ${s.code}`)}><Trash2 size={14} /></button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
      <div><button className="btn" onClick={() => setUcForm("new")}><Plus size={15} /> Add use case</button></div>

      {ucForm && <UseCaseForm event={event} uc={ucForm === "new" ? undefined : ucForm} onClose={() => setUcForm(null)}
        onSaved={() => { setUcForm(null); void reload(); }} />}
      {stepForm && <StepEditor uc={stepForm.uc} step={stepForm.step} onClose={() => setStepForm(null)}
        onSaved={() => { setStepForm(null); void reload(); }} />}
    </div>
  );
}

function UseCaseForm({ event, uc, onClose, onSaved }: { event: EventDetail; uc?: UseCaseDef; onClose: () => void; onSaved: () => void }) {
  const [code, setCode] = useState(uc?.code ?? "");
  const [title, setTitle] = useState(uc?.title ?? "");
  const [description, setDescription] = useState(uc?.description ?? "");
  const [order, setOrder] = useState(uc?.sort_order ?? event.use_cases.length);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    try {
      const body = { code, title, description: description || null, sort_order: order };
      if (uc) await api.patch(`/api/admin/use-cases/${uc.id}`, body);
      else await api.post(`/api/admin/events/${event.id}/use-cases`, body);
      onSaved();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : String(e));
    }
  }

  return (
    <Modal title={uc ? "Edit use case" : "New use case"} onClose={onClose} footer={
      <><button className="btn" onClick={onClose}>Cancel</button><button className="btn btn-primary" disabled={!code || title.length < 2} onClick={() => void save()}>Save</button></>
    }>
      <div className="stack">
        <ErrorAlert error={error} />
        <div className="field"><label>use_case_id</label><input className="input mono" value={code} disabled={!!uc} onChange={(e) => setCode(e.target.value)} placeholder="cowork-sales-brief" /></div>
        <div className="field"><label>Title</label><input className="input" value={title} onChange={(e) => setTitle(e.target.value)} /></div>
        <div className="field"><label>Description</label><textarea className="textarea" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} /></div>
        <div className="field"><label>Order</label><input type="number" className="input" value={order} onChange={(e) => setOrder(Number(e.target.value))} /></div>
      </div>
    </Modal>
  );
}

function StepEditor({ uc, step, onClose, onSaved }: { uc: UseCaseDef; step?: StepDef; onClose: () => void; onSaved: () => void }) {
  const [code, setCode] = useState(step?.code ?? `step-${uc.steps.length + 1}`);
  const [title, setTitle] = useState(step?.title ?? "");
  const [description, setDescription] = useState(step?.description ?? "");
  const [order, setOrder] = useState(step?.sort_order ?? uc.steps.length);
  const [yaml, setYaml] = useState(step?.rubric_yaml || STARTER);
  const [error, setError] = useState<{ message: string; details?: string[] } | null>(null);
  const [valid, setValid] = useState<boolean | null>(null);
  const { data: types } = useLoad(() => api.get<CheckType[]>("/api/admin/check-types"));

  async function validate() {
    const r = await api.post<{ valid: boolean; errors: string[] }>("/api/admin/rubrics/validate", { rubric_yaml: yaml });
    setValid(r.valid);
    setError(r.valid ? null : { message: "Rubric is invalid", details: r.errors });
  }

  async function save() {
    setError(null);
    try {
      const body = { title, description: description || null, sort_order: order, rubric_yaml: yaml };
      if (step) await api.patch(`/api/admin/steps/${step.id}`, body);
      else await api.post(`/api/admin/use-cases/${uc.id}/steps`, { ...body, code });
      onSaved();
    } catch (e) {
      setError(e instanceof ApiError ? { message: e.message, details: e.details } : { message: String(e) });
    }
  }

  return (
    <Modal wide title={step ? `${uc.code} / ${step.code}` : `New step in ${uc.code}`} onClose={onClose} footer={
      <>
        <button className="btn" onClick={() => void validate()}><FileCode2 size={15} /> Validate rubric</button>
        <span className="grow" />
        <button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" disabled={title.length < 2} onClick={() => void save()}>Save step</button>
      </>
    }>
      <div className="stack">
        <ErrorAlert error={error?.message ?? null} details={error?.details} />
        {valid && <div className="alert alert-ok"><CheckCircle2 size={18} /> Rubric is valid.</div>}
        <div className="grid grid-3">
          <div className="field"><label>step_id</label><input className="input mono" value={code} disabled={!!step} onChange={(e) => setCode(e.target.value)} /></div>
          <div className="field" style={{ gridColumn: "span 2" }}><label>Title</label><input className="input" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Draft the account brief" /></div>
        </div>
        <div className="grid grid-3">
          <div className="field" style={{ gridColumn: "span 2" }}><label>Description</label><input className="input" value={description} onChange={(e) => setDescription(e.target.value)} /></div>
          <div className="field"><label>Order</label><input type="number" className="input" value={order} onChange={(e) => setOrder(Number(e.target.value))} /></div>
        </div>
        <div className="field">
          <label>Rubric (YAML)</label>
          <textarea className="textarea code-editor" spellCheck={false} value={yaml} onChange={(e) => { setYaml(e.target.value); setValid(null); }} />
          <span className="hint">
            mode: blocking (decides the result) or deferred (slow Copilot evidence, re-verified in the background).
            retry_window_seconds: keep re-checking a failing blocking check this long to absorb Graph propagation delay.
          </span>
        </div>
        <details>
          <summary className="faint" style={{ cursor: "pointer" }}>Available check types</summary>
          <div className="stack mt">
            {types?.map((t) => (
              <div key={t.type} className="check-item">
                <div className="grow">
                  <div className="row-between"><b>{t.title}</b><code>{t.type}</code></div>
                  <div className="small muted">{t.summary}</div>
                  <pre className="json" style={{ marginTop: 6 }}>{`params: ${JSON.stringify(t.example)}`}</pre>
                </div>
              </div>
            ))}
          </div>
        </details>
      </div>
    </Modal>
  );
}
