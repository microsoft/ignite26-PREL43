import { useState, type ReactNode } from "react";
import { AlertTriangle, Check, CheckCircle2, CircleDashed, Clock, Copy, Loader2, Minus, Search as SearchIcon, X, XCircle } from "lucide-react";
import type { StepState, SubStatus } from "../lib/types";

export function StatusBadge({ status }: { status: SubStatus | StepState | string }) {
  const map: Record<string, [string, string]> = {
    complete: ["b-ok", "Complete"],
    incomplete: ["b-bad", "Incomplete"],
    error: ["b-warn", "Error"],
    queued: ["b-info", "Queued"],
    evaluating: ["b-info", "Evaluating"],
    not_started: ["b-muted", "Not started"],
    live: ["b-ok", "Live"],
    draft: ["b-muted", "Draft"],
    closed: ["b-muted", "Closed"],
    active: ["b-ok", "Active"],
    revoked: ["b-bad", "Revoked"],
    delivered: ["b-ok", "Delivered"],
    pending: ["b-info", "Pending"],
    failed: ["b-bad", "Failed"],
  };
  const [cls, label] = map[status] ?? ["b-muted", status];
  const animated = status === "evaluating" || status === "queued" || status === "live";
  return (
    <span className={`badge ${cls}`}>
      <span className={`dot ${animated ? "pulse" : ""}`} />
      {label}
    </span>
  );
}

export function VerificationBadge({ status }: { status: string }) {
  if (!status || status === "not_required") return null;
  const map: Record<string, [string, string, string]> = {
    verified: ["b-ok", "Copilot verified", "Deferred Copilot evidence confirmed"],
    pending: ["b-info", "Verifying", "Waiting for slower Copilot evidence (e.g. Purview audit)"],
    unverified: ["b-warn", "Not verified", "Copilot evidence never appeared; review manually"],
  };
  const [cls, label, title] = map[status] ?? ["b-muted", status, ""];
  return (
    <span className={`badge ${cls}`} title={title}>
      {label}
    </span>
  );
}

export function StepCell({ state, title }: { state: StepState; title?: string }) {
  const icon = {
    complete: <Check size={15} strokeWidth={3} />,
    incomplete: <X size={15} strokeWidth={3} />,
    error: <AlertTriangle size={13} />,
    evaluating: <Loader2 size={13} className="spin" />,
    not_started: <Minus size={13} />,
  }[state];
  return (
    <span className={`matrix-cell m-${state}`} title={title}>
      {icon}
    </span>
  );
}

export function CheckIcon({ status }: { status: string }) {
  if (status === "passed") return <CheckCircle2 size={18} />;
  if (status === "failed") return <XCircle size={18} />;
  if (status === "pending") return <Clock size={18} />;
  if (status === "error") return <AlertTriangle size={18} />;
  return <CircleDashed size={18} />;
}

export function Modal({ title, onClose, children, footer, wide }: {
  title: ReactNode; onClose: () => void; children: ReactNode; footer?: ReactNode; wide?: boolean;
}) {
  return (
    <div className="overlay" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className={`modal ${wide ? "modal-wide" : ""}`} role="dialog" aria-modal="true">
        <div className="modal-head">
          <h3>{title}</h3>
          <button className="btn btn-ghost icon-btn" onClick={onClose} aria-label="Close">
            <X size={18} />
          </button>
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-foot">{footer}</div>}
      </div>
    </div>
  );
}

export function Drawer({ onClose, children }: { onClose: () => void; children: ReactNode }) {
  return (
    <div className="overlay drawer-overlay" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="drawer" role="dialog" aria-modal="true">
        {children}
      </div>
    </div>
  );
}

export function CopyButton({ value, label }: { value: string; label?: string }) {
  const [done, setDone] = useState(false);
  return (
    <button
      type="button"
      className="btn btn-sm"
      onClick={async () => {
        await navigator.clipboard.writeText(value);
        setDone(true);
        setTimeout(() => setDone(false), 1500);
      }}
    >
      {done ? <Check size={14} /> : <Copy size={14} />}
      {label ?? (done ? "Copied" : "Copy")}
    </button>
  );
}

export function SecretField({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="field">
      <label>{label}</label>
      <div className="secret-box">
        <span className="grow">{value}</span>
        <CopyButton value={value} />
      </div>
      {hint && <span className="hint">{hint}</span>}
    </div>
  );
}

export function Empty({ icon, title, children }: { icon: ReactNode; title: string; children?: ReactNode }) {
  return (
    <div className="empty">
      <div className="empty-icon">{icon}</div>
      <h3>{title}</h3>
      <div>{children}</div>
    </div>
  );
}

export function Loading() {
  return (
    <div className="empty">
      <Loader2 className="spin" size={22} />
    </div>
  );
}

export function ErrorAlert({ error, details }: { error: string | null; details?: string[] }) {
  if (!error) return null;
  return (
    <div className="alert alert-bad">
      <AlertTriangle size={18} style={{ flexShrink: 0, marginTop: 1 }} />
      <div>
        {error}
        {details && details.length > 0 && (
          <ul>
            {details.map((d) => (
              <li key={d}>{d}</li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

export type Tone = "blue" | "orange" | "purple" | "pink" | "green" | "muted";

export function Stat({ icon, tone = "blue", label, value, foot, selected }: {
  icon: ReactNode; tone?: Tone; label: string; value: ReactNode; foot?: ReactNode; selected?: boolean;
}) {
  return (
    <div className={`card stat ${selected ? "selected" : ""}`}>
      <span className={`tone tone-${tone} stat-icon`}>{icon}</span>
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
      {foot && <div className="stat-foot">{foot}</div>}
    </div>
  );
}

export function Search({ value, onChange, placeholder, width }: {
  value: string; onChange: (v: string) => void; placeholder: string; width?: number;
}) {
  return (
    <div className="search" style={width ? { width } : undefined}>
      <SearchIcon size={15} />
      <input className="input" value={value} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} />
    </div>
  );
}

export function LiveIndicator({ connected, lastUpdate }: { connected: boolean; lastUpdate: Date | null }) {
  return (
    <span className={`live ${connected ? "on" : "off"}`} title={lastUpdate ? `Last update ${lastUpdate.toLocaleTimeString()}` : ""}>
      <span className={`dot ${connected ? "pulse" : ""}`} />
      {connected ? "Live" : "Reconnecting"}
    </span>
  );
}
