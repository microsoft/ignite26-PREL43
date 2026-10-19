import { useEffect, useState } from "react";

export type Theme = "light" | "dark";
const KEY = "vs_theme";

function read(): Theme {
  try {
    return window.localStorage.getItem(KEY) === "dark" ? "dark" : "light";
  } catch {
    return "light";
  }
}

export function applyStoredTheme(): void {
  document.documentElement.setAttribute("data-theme", read());
}

/** Light by default; the toggle choice is remembered per browser. */
export function useTheme(): [Theme, () => void] {
  const [theme, setTheme] = useState<Theme>(read);
  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    try {
      window.localStorage.setItem(KEY, theme);
    } catch {
      /* storage unavailable: theme still applies for this page view */
    }
  }, [theme]);
  return [theme, () => setTheme((t) => (t === "light" ? "dark" : "light"))];
}
