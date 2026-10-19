import { useState, type FormEvent } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { ArrowRight, ShieldCheck } from "lucide-react";
import { ErrorAlert } from "@shared/components/ui";
import { entraLogin, isSignedIn, localLogin } from "../lib/auth";
import { config } from "@shared/lib/config";

export default function Login() {
  const nav = useNavigate();
  const cfg = config();
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (isSignedIn()) return <Navigate to="/" replace />;

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await localLogin(username, password);
      nav("/", { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Sign-in failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <div className="login-art">
        <div className="row">
          <img src="/logo.svg" alt="" width={34} height={34} style={{ borderRadius: 8 }} />
          <div style={{ fontWeight: 600, fontSize: 16 }}>VectorSense Labs</div>
        </div>
        <div>
          <div className="hero-eyebrow">Scoring Engine</div>
          <h1>Proof of work, not proof of clicks.</h1>
          <p>
            Lab platforms call one API when a participant clicks Complete. VectorSense checks the real evidence in
            Microsoft 365 and answers complete or incomplete, with the reason why.
          </p>
        </div>
        <div style={{ opacity: 0.75, fontSize: 12.5 }}>Any lab vendor · Any tenant · One contract</div>
      </div>
      <div className="login-form">
        <div className="login-card stack">
          <div>
            <h2 style={{ fontSize: 24 }}>Sign in</h2>
            <div className="muted">Administrator access to the scoring console</div>
          </div>
          <ErrorAlert error={error} />
          {cfg.auth_mode === "entra" ? (
            <button className="btn btn-primary" style={{ height: 44 }} onClick={() => void entraLogin()}>
              <ShieldCheck size={18} /> Sign in with Microsoft Entra ID
            </button>
          ) : (
            <form className="stack" onSubmit={submit}>
              <div className="field">
                <label htmlFor="u">Username</label>
                <input id="u" className="input" value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" />
              </div>
              <div className="field">
                <label htmlFor="p">Password</label>
                <input id="p" className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                  autoComplete="current-password" autoFocus />
              </div>
              <button className="btn btn-primary" style={{ height: 42 }} disabled={busy}>
                Sign in <ArrowRight size={16} />
              </button>
              <div className="faint small">Local sign-in is for test environments. Production uses Entra ID.</div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
