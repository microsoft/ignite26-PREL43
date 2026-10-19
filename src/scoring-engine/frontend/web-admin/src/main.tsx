import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { initAuth } from "./lib/auth";
import { loadConfig } from "@shared/lib/config";
import { applyStoredTheme } from "@shared/lib/theme";
import "@shared/styles.css";

applyStoredTheme();
const root = createRoot(document.getElementById("root")!);

loadConfig()
  .then(initAuth)
  .then(() =>
    root.render(
      <StrictMode>
        <App />
      </StrictMode>,
    ),
  )
  .catch((e: Error) => {
    root.render(
      <div style={{ padding: 40, fontFamily: "Inter, sans-serif" }}>
        <h2>VectorSense Labs - Scoring Engine</h2>
        <p>The service is not reachable right now: {e.message}</p>
      </div>,
    );
  });
