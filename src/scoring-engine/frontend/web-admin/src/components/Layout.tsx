import { useState, type ReactNode } from "react";
import { Link, NavLink, Outlet, useLocation } from "react-router-dom";
import { BookOpen, CalendarRange, ChevronRight, Home, IdCard, KeyRound, LogOut, ServerCog } from "lucide-react";
import { TopBar } from "@shared/components/TopBar";
import { config } from "@shared/lib/config";
import { initials } from "@shared/lib/format";
import { displayName, signOut } from "../lib/auth";

const SECTIONS: Record<string, string> = {
  "": "Home",
  events: "Events",
  integrations: "Integrations",
  system: "System",
};

function UserMenu() {
  const [open, setOpen] = useState(false);
  const name = config().auth_mode === "entra" ? displayName() : "Administrator";
  return (
    <div style={{ position: "relative" }}>
      <button className="top-icon" onClick={() => setOpen((o) => !o)} aria-label="Account">
        <span className="top-user">{initials(name)}</span>
      </button>
      {open && (
        <div className="menu" onMouseLeave={() => setOpen(false)}>
          <div className="menu-head">
            <div style={{ fontWeight: 600 }}>{name}</div>
            <div className="faint small">Scoring Engine administrator</div>
          </div>
          <button onClick={signOut}><LogOut size={15} /> Sign out</button>
        </div>
      )}
    </div>
  );
}

export default function Layout() {
  const { pathname } = useLocation();
  const section = SECTIONS[pathname.split("/")[1] ?? ""] ?? "Home";
  return (
    <div className="app">
      <TopBar
        area="Scoring Engine"
        current={section}
        right={
          <>
            <a className="top-icon" href="/api/docs" target="_blank" rel="noreferrer" title="API reference"><BookOpen size={17} /></a>
            <UserMenu />
          </>
        }
      />
      <div className="body">
        <nav className="rail">
          <NavLink to="/" end><span className="rail-icon"><Home size={17} /></span>Home</NavLink>
          <NavLink to="/events"><span className="rail-icon"><CalendarRange size={17} /></span>Events</NavLink>
          <NavLink to="/integrations"><span className="rail-icon"><KeyRound size={17} /></span>Integrations</NavLink>
          <NavLink to="/system"><span className="rail-icon"><ServerCog size={17} /></span>System</NavLink>
          <span className="rail-spacer" />
          <a href={config().scorecard_base_url} target="_blank" rel="noreferrer" title="Participant scorecard">
            <span className="rail-icon"><IdCard size={17} /></span>Scorecard
          </a>
        </nav>
        <main className="content">
          <div className="page">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
}

export function PageHeader({ title, sub, crumbs, actions }: {
  title: ReactNode; sub?: ReactNode; crumbs?: { label: string; to?: string }[]; actions?: ReactNode;
}) {
  return (
    <>
      {crumbs && (
        <div className="crumbs">
          <Link to="/" aria-label="Home"><Home size={13} /></Link>
          {crumbs.map((c) => (
            <span key={c.label} className="row" style={{ gap: 8 }}>
              <ChevronRight size={12} className="sep" />
              {c.to ? <Link to={c.to}>{c.label}</Link> : <span>{c.label}</span>}
            </span>
          ))}
        </div>
      )}
      <div className="page-head">
        <div>
          <h1 className="page-title">{title}</h1>
          {sub && <div className="page-sub">{sub}</div>}
        </div>
        {actions && <div className="row">{actions}</div>}
      </div>
    </>
  );
}
