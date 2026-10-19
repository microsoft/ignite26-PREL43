import { useCallback, useEffect, useState, type FormEvent } from "react";
import { Link, useParams } from "react-router-dom";
import {
  ArrowRight, CheckCircle2, Clock, IdCard, Loader2, LogOut, MinusCircle, Percent, RefreshCw, XCircle,
} from "lucide-react";
import { TopBar } from "@shared/components/TopBar";
import { CheckIcon, ErrorAlert, LiveIndicator, Loading, Stat, StatusBadge } from "@shared/components/ui";
import { dateTime, duration, relTime } from "@shared/lib/format";
import { useLiveUpdates, useLoad } from "@shared/lib/hooks";
import { api, ApiError } from "../lib/api";

interface EventMeta { slug: string; name: string; description: string | null; status: string }
interface Card {
  event: { slug: string; name: string; status: string; last_synced_at: string | null };
  participant: { name: string; upn: string };
  completed_steps: number;
  total_steps: number;
  elapsed_seconds: number | null;
  steps: {
    use_case: string; code: string; title: string; description: string | null; status: string; attempts: number;
    completed_at: string | null; verification_status: string;
    reasons: { check: string; message: string }[];
    checks: { id: string; description: string; status: string; mode: string; message: string }[];
  }[];
}

const storeKey = (slug: string) => `vs_scorecard_${slug}`;
function remembered(slug: string): string {
  try {
    return window.sessionStorage.getItem(storeKey(slug)) ?? "";
  } catch {
    return "";
  }
}
function remember(slug: string, upn: string | null) {
  try {
    if (upn) window.sessionStorage.setItem(storeKey(slug), upn);
    else window.sessionStorage.removeItem(storeKey(slug));
  } catch {
    /* storage unavailable: the participant just re-enters their account */
  }
}

function StepIcon({ status }: { status: string }) {
  if (status === "complete") return <CheckCircle2 size={22} color="var(--ok)" />;
  if (status === "incomplete") return <XCircle size={22} color="var(--bad)" />;
  if (status === "evaluating") return <Loader2 size={22} color="var(--info)" className="spin" />;
  return <MinusCircle size={22} color="var(--text-3)" />;
}

function AccountPrompt({ event, initial, onFound }: { event: EventMeta; initial: string; onFound: (upn: string, card: Card) => void }) {
  const [upn, setUpn] = useState(initial);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const card = await api.post<Card>(`/api/public/events/${event.slug}/scorecard`, { upn: upn.trim() });
      onFound(upn.trim(), card);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Something went wrong. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="overlay">
      <form className="modal" onSubmit={submit} role="dialog" aria-modal="true" aria-labelledby="acct-title">
        <div className="modal-head">
          <div className="row">
            <span className="tone tone-blue"><IdCard size={16} /></span>
            <div>
              <h3 id="acct-title">View your scorecard</h3>
              <div className="faint small">{event.name}</div>
            </div>
          </div>
        </div>
        <div className="modal-body stack">
          <ErrorAlert error={error} />
          <div className="field">
            <label htmlFor="upn">Lab account</label>
            <input id="upn" className="input" autoFocus autoComplete="username" placeholder="labuser0421@yourlabtenant.onmicrosoft.com"
              value={upn} onChange={(e) => setUpn(e.target.value)} />
            <span className="hint">The account you sign in to the lab with. It is shown on your lab's instructions or resources tab.</span>
          </div>
        </div>
        <div className="modal-foot">
          <button className="btn btn-primary" disabled={busy || !upn.includes("@")}>
            {busy ? <Loader2 size={15} className="spin" /> : <ArrowRight size={15} />} Show my scorecard
          </button>
        </div>
      </form>
    </div>
  );
}

export default function Scorecard() {
  const { slug = "" } = useParams();
  const meta = useLoad(() => api.get<EventMeta>(`/api/public/events/${slug}`), [slug]);
  const [upn, setUpn] = useState<string>(() => remembered(slug));
  const [card, setCard] = useState<Card | null>(null);
  const [prompt, setPrompt] = useState(!remembered(slug));
  const [loadError, setLoadError] = useState<string | null>(null);
  const [refreshedAt, setRefreshedAt] = useState<Date | null>(null);

  const refresh = useCallback(async () => {
    if (!upn) return;
    try {
      setCard(await api.post<Card>(`/api/public/events/${slug}/scorecard`, { upn }));
      setRefreshedAt(new Date());
      setLoadError(null);
    } catch (e) {
      if (e instanceof ApiError && e.status === 404) {
        remember(slug, null);
        setPrompt(true);
      } else {
        setLoadError(e instanceof Error ? e.message : String(e));
      }
    }
  }, [slug, upn]);

  useEffect(() => {
    if (upn && !prompt && !card) void refresh();
  }, [upn, prompt, card, refresh]);

  const live = useLiveUpdates(card ? `/api/public/events/${slug}/stream` : null, () => void refresh(), 500);

  const signOut = () => {
    remember(slug, null);
    setCard(null);
    setPrompt(true);
  };

  if (meta.error) {
    return (
      <div className="app">
        <TopBar area="Scorecard" />
        <div className="pub-body">
          <div className="hero"><div className="hero-eyebrow">Scorecard</div><h1>Not available</h1>
            <p>This event does not exist or its scorecards are not open yet. <Link to="/" style={{ color: "#fff", textDecoration: "underline" }}>See all events</Link></p></div>
        </div>
      </div>
    );
  }
  const event = meta.data;
  const pct = card ? Math.round((card.completed_steps / Math.max(card.total_steps, 1)) * 100) : 0;
  const groups = (card?.steps ?? []).reduce<Record<string, Card["steps"]>>((acc, s) => ((acc[s.use_case] ??= []).push(s), acc), {});

  return (
    <div className="app">
      <TopBar
        area="Scorecard"
        current={event?.name}
        right={card && (
          <>
            <LiveIndicator {...live} />
            <button className="top-icon" style={{ width: "auto", padding: "0 10px", borderRadius: 8, gap: 6, display: "inline-flex", fontSize: 13, fontWeight: 600 }}
              onClick={signOut} title="Use a different lab account">
              <LogOut size={15} /> Switch account
            </button>
          </>
        )}
      />
      <div className="pub-body">
        {!event ? <Loading /> : (
          <>
            <div className="hero">
              <div className="hero-eyebrow">Your scorecard · {event.name}</div>
              <h1>{card ? card.participant.name : "Your lab progress"}</h1>
              <p>{card ? <>Lab account <b>{card.participant.upn}</b>. This page updates on its own as your steps are checked.</>
                : event.description ?? "Enter your lab account to see which steps are complete and what is left to do."}</p>
            </div>
            <ErrorAlert error={loadError} />
            {card && (
              <>
                <div className="grid grid-4">
                  <Stat tone="blue" icon={<CheckCircle2 size={16} />} value={`${card.completed_steps}/${card.total_steps}`} label="Steps Complete" foot="Verified from your lab work" />
                  <Stat tone="orange" icon={<Percent size={16} />} value={`${pct}%`} label="Progress"
                    foot={<div className="progress" style={{ marginTop: 6 }}><span style={{ width: `${pct}%` }} /></div>} />
                  <Stat tone="purple" icon={<Clock size={16} />} value={duration(card.elapsed_seconds)} label="Time" foot="Lab start to last completed step" />
                  <Stat tone="pink" icon={<RefreshCw size={16} />} value={refreshedAt ? refreshedAt.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : "—"}
                    label="Last Updated" foot={card.event.last_synced_at ? `Organiser sync ${relTime(card.event.last_synced_at)}` : "Updates as you click Complete"} />
                </div>

                {Object.entries(groups).map(([useCase, steps]) => (
                  <div key={useCase}>
                    <div className="section-head mt-lg"><h2>{useCase}</h2></div>
                    <div className="stack" style={{ gap: 10 }}>
                      {steps.map((s) => (
                        <div key={s.code} className={`card step-card ${s.status}`}>
                          <div className="row-between wrap">
                            <div className="row">
                              <StepIcon status={s.status} />
                              <div>
                                <div style={{ fontWeight: 600 }}>{s.title}</div>
                                <div className="cell-sub">
                                  {s.code}{s.attempts ? ` · ${s.attempts} attempt${s.attempts > 1 ? "s" : ""}` : ""}
                                  {s.completed_at ? ` · completed ${dateTime(s.completed_at)}` : ""}
                                </div>
                              </div>
                            </div>
                            <div className="row">
                              {s.verification_status === "pending" && <span className="badge b-info" title="Slower Copilot evidence is still being confirmed. This does not change your result.">Verifying Copilot use</span>}
                              {s.verification_status === "verified" && <span className="badge b-ok">Copilot verified</span>}
                              <StatusBadge status={s.status} />
                            </div>
                          </div>
                          {s.status === "incomplete" && s.reasons.map((r) => (
                            <div className="reason" key={r.check}><b>Why not complete:</b> {r.message}</div>
                          ))}
                          {s.status === "incomplete" && s.reasons.length > 0 && (
                            <div className="cell-sub" style={{ marginTop: 8 }}>Fix this in your lab, then click Complete again.</div>
                          )}
                          {s.checks.length > 0 && (
                            <details style={{ marginTop: 10 }}>
                              <summary className="small faint" style={{ cursor: "pointer" }}>What we checked</summary>
                              <div className="stack" style={{ marginTop: 10, gap: 8 }}>
                                {s.checks.map((c) => (
                                  <div key={c.id} className={`check-item ${c.status}`}>
                                    <span className="ci-icon"><CheckIcon status={c.status} /></span>
                                    <div className="small">
                                      <div style={{ fontWeight: 600 }}>{c.description}{c.mode === "deferred" && <span className="faint" style={{ fontWeight: 400 }}> · background verification</span>}</div>
                                      <div className="muted">{c.message}</div>
                                    </div>
                                  </div>
                                ))}
                              </div>
                            </details>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                ))}
              </>
            )}
            {!card && !prompt && !loadError && <Loading />}
            {prompt && (
              <AccountPrompt event={event} initial={upn} onFound={(u, c) => {
                remember(slug, u);
                setUpn(u);
                setCard(c);
                setRefreshedAt(new Date());
                setPrompt(false);
              }} />
            )}
          </>
        )}
        <div className="pub-foot">VectorSense Labs · Scoring Engine · Only you can see this scorecard</div>
      </div>
    </div>
  );
}
