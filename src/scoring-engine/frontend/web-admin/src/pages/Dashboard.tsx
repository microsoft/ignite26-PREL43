import { useEffect, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
import {
  Activity, AlertCircle, CalendarRange, CheckCircle2, ChevronRight, Cpu, FileWarning, Inbox, KeyRound, RefreshCw,
  ShieldQuestion, Users, Webhook, XCircle,
} from "lucide-react";
import { ErrorAlert, Loading, Stat, StatusBadge } from "@shared/components/ui";
import { api } from "../lib/api";
import { config } from "@shared/lib/config";
import { relTime } from "@shared/lib/format";
import { useLoad } from "@shared/lib/hooks";
import type { Overview } from "@shared/lib/types";

interface DashboardData extends Overview {
  unverified: number;
  steps_without_rubric: number;
  integrations_never_used: number;
  webhooks_failed: number;
  live_event_id: string | null;
}
interface GraphStatus { ok: boolean; mode?: string; tenant_name?: string; error?: string }

function greeting(): string {
  const h = new Date().getHours();
  return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening";
}

function Item({ icon, title, sub, count, tone = "bad", to }: {
  icon: ReactNode; title: string; sub: string; count: number; tone?: "bad" | "warn" | "info"; to?: string;
}) {
  const body = (
    <>
      <span className="pi-icon">{icon}</span>
      <div className="grow">
        <div className="pi-title">{title}</div>
        <div className="pi-sub">{sub}</div>
      </div>
      {count > 0 ? <span className={`count count-${tone}`}>{count}</span>
        : <span className="all-clear"><CheckCircle2 size={14} /> All clear</span>}
      <ChevronRight size={16} className="chev" />
    </>
  );
  return to ? <Link to={to} className="panel-item">{body}</Link> : <div className="panel-item">{body}</div>;
}

export default function Dashboard() {
  const { data, error, reload } = useLoad(() => api.get<DashboardData>("/api/admin/overview"));
  const graph = useLoad(() => api.get<GraphStatus>("/api/admin/graph/status"));
  const [updated, setUpdated] = useState(new Date());

  useEffect(() => {
    const t = window.setInterval(() => { void reload(); setUpdated(new Date()); }, 10000);
    return () => window.clearInterval(t);
  }, [reload]);

  const evaluated = data ? data.by_status.complete + data.by_status.incomplete + data.by_status.error : 0;
  const rate = data && evaluated ? Math.round((data.by_status.complete / evaluated) * 100) : 0;
  const eventLink = data?.live_event_id ? `/events/${data.live_event_id}` : "/events";
  const scoringOpen = data ? [data.by_status.error, data.unverified, data.by_status.incomplete].filter(Boolean).length : 0;
  const setupOpen = data ? [data.steps_without_rubric, data.integrations_never_used, data.webhooks_failed].filter(Boolean).length : 0;

  return (
    <>
      <div className="hero">
        <div className="hero-eyebrow">Scoring Engine</div>
        <h1>{greeting()}, {config().auth_mode === "entra" ? "there" : "Administrator"}</h1>
        <p>Here's what needs your attention: evaluation results, live events, vendor integrations and evidence-source health.</p>
      </div>

      <div className="section-head">
        <div>
          <h2>Right now</h2>
          <div className="sub">Updated {updated.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</div>
        </div>
        <button className="btn" onClick={() => { void reload(); void graph.reload(); setUpdated(new Date()); }}>
          <RefreshCw size={15} /> Refresh
        </button>
      </div>

      <ErrorAlert error={error} />
      {!data ? <Loading /> : (
        <>
          <div className="grid grid-4">
            <Stat tone="blue" icon={<CalendarRange size={16} />} value={data.live_events} label="Events Live Now"
              foot={`${data.events} total · ${data.integrations} active integration${data.integrations === 1 ? "" : "s"}`} />
            <Stat tone="orange" icon={<Users size={16} />} value={data.participants.toLocaleString()} label="Participants Scored"
              foot="Seen through Complete clicks" selected />
            <Stat tone="purple" icon={<Activity size={16} />} value={data.submissions_last_hour.toLocaleString()} label="Complete Clicks · Last Hour"
              foot={`${data.submissions.toLocaleString()} all time`} />
            <Stat tone="pink" icon={<CheckCircle2 size={16} />} value={`${rate}%`} label="Completion Rate"
              foot={`${data.by_status.complete.toLocaleString()} complete of ${evaluated.toLocaleString()} evaluated`} />
          </div>

          <div className="split mt">
            <div className="card">
              <div className="panel-head">
                <div>
                  <h3><AlertCircle size={16} className="faint" /> Needs Attention</h3>
                  <div className="sub">By area, most urgent first · now</div>
                </div>
                <span className="badge b-bad">{scoringOpen + setupOpen} open</span>
              </div>
              <div className="panel-section">Scoring &amp; Evidence <span className={`count ${scoringOpen ? "count-bad" : "count-info"}`}>{scoringOpen} open</span></div>
              <Item icon={<XCircle size={15} />} title="Evaluation errors" sub="Evidence could not be read after retries" count={data.by_status.error} to={eventLink} />
              <Item icon={<ShieldQuestion size={15} />} title="Copilot evidence never confirmed" sub="Complete steps whose deferred Copilot check expired" count={data.unverified} tone="warn" to={eventLink} />
              <Item icon={<Inbox size={15} />} title="Incomplete results" sub="Participants told what to fix; may retry" count={data.by_status.incomplete} tone="info" to={eventLink} />
              <div className="panel-section">Setup &amp; Integrations <span className={`count ${setupOpen ? "count-warn" : "count-info"}`}>{setupOpen} open</span></div>
              <Item icon={<FileWarning size={15} />} title="Steps without a rubric" sub="Complete calls for these steps return 409" count={data.steps_without_rubric} tone="warn" to="/events" />
              <Item icon={<KeyRound size={15} />} title="Integrations never used" sub="Credentials issued, no token requested yet" count={data.integrations_never_used} tone="info" to="/integrations" />
              <Item icon={<Webhook size={15} />} title="Failed result webhooks" sub="Vendor endpoint rejected all retries" count={data.webhooks_failed} to="/integrations" />
            </div>

            <div className="card">
              <div className="panel-head">
                <div>
                  <h3><Cpu size={16} className="faint" /> Platform</h3>
                  <div className="sub">Evidence source and evaluation health</div>
                </div>
              </div>
              <div className="kv-item">
                <span className="tone tone-muted"><Activity size={15} /></span>
                <div className="grow">
                  <div className="k">Evaluation queue</div>
                  <div className="v">{data.by_status.queued + data.by_status.evaluating} in progress</div>
                  <div className="faint small">{data.pending_verification} awaiting Copilot verification</div>
                </div>
              </div>
              <div className="kv-item">
                <span className="tone tone-muted"><Cpu size={15} /></span>
                <div className="grow">
                  <div className="k">Microsoft Graph</div>
                  <div className="v">{!graph.data ? "Checking…" : graph.data.ok ? (graph.data.mode === "mock" ? "Mock evidence" : "Connected") : "Unavailable"}</div>
                  <div className="faint small">{graph.data?.ok ? graph.data.tenant_name : graph.data?.error ?? ""}</div>
                </div>
                <Link to="/system" className="small" style={{ fontWeight: 600, alignSelf: "center" }}>System</Link>
              </div>
              <div className="kv-item">
                <span className="tone tone-muted"><KeyRound size={15} /></span>
                <div className="grow">
                  <div className="k">Admin sign-in</div>
                  <div className="v">{config().auth_mode === "entra" ? "Microsoft Entra ID" : "Local (test only)"}</div>
                </div>
              </div>
            </div>
          </div>

          <div className="section-head mt-lg">
            <div>
              <h2>Latest Complete clicks</h2>
              <div className="sub">Across all events and vendors</div>
            </div>
          </div>
          <div className="card">
            <div className="table-wrap">
              <table className="table">
                <thead>
                  <tr><th>Participant</th><th>Event</th><th>Step</th><th>Result</th><th>Why</th><th className="num">Received</th></tr>
                </thead>
                <tbody>
                  {data.recent.length === 0 && (
                    <tr><td colSpan={6} className="faint">No submissions yet. Create an integration and point a lab vendor at the API.</td></tr>
                  )}
                  {data.recent.map((s) => (
                    <tr key={s.id}>
                      <td><div style={{ fontWeight: 500 }}>{s.participant}</div><div className="cell-sub">{s.upn}</div></td>
                      <td><Link to={`/events/${s.event_id}`}>{s.event_slug}</Link></td>
                      <td>{s.step_title}<div className="cell-sub mono">{s.use_case}/{s.step}</div></td>
                      <td><StatusBadge status={s.status} /></td>
                      <td className="small muted" style={{ maxWidth: 340 }}>{s.reasons[0]?.message ?? ""}</td>
                      <td className="num faint small">{relTime(s.received_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </>
  );
}
