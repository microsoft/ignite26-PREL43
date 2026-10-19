import type { ReactNode } from "react";
import { LayoutGrid, Moon, Sun } from "lucide-react";
import { config } from "../lib/config";
import { useTheme } from "../lib/theme";

export function ThemeToggle() {
  const [theme, toggle] = useTheme();
  return (
    <button className="top-icon" onClick={toggle} title={theme === "light" ? "Switch to dark mode" : "Switch to light mode"}
      aria-label="Toggle dark mode">
      {theme === "light" ? <Moon size={17} /> : <Sun size={17} />}
    </button>
  );
}

/** Blue application bar shared by the admin portal and the participant scorecard. */
export function TopBar({ area, current, right, homeHref = "/" }: {
  area: string; current?: ReactNode; right?: ReactNode; homeHref?: string;
}) {
  const env = config().environment;
  return (
    <header className="topbar">
      <a href={homeHref} className="topbar-apps top-icon" style={{ borderRadius: 0, width: 80, height: 56 }} aria-label="Home">
        <LayoutGrid size={19} />
      </a>
      <div className="topbar-mark">
        <img src="/logo.svg" alt="VectorSense Labs" />
      </div>
      <div className="topbar-crumb">
        <span className="env-badge">{env === "production" ? "PROD" : env}</span>
        <b>{area}</b>
        {current && <><span className="sep">/</span><span className="cur">{current}</span></>}
      </div>
      <div className="topbar-actions">
        {right}
        <ThemeToggle />
      </div>
    </header>
  );
}
