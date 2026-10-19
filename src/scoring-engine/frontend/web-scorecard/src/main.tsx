import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { loadConfig } from "@shared/lib/config";
import { applyStoredTheme } from "@shared/lib/theme";
import App from "./App";
import "@shared/styles.css";

applyStoredTheme();
const root = createRoot(document.getElementById("root")!);

loadConfig()
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
        <h2>VectorSense Labs - Scorecard</h2>
        <p>The service is not reachable right now: {e.message}</p>
      </div>,
    );
  });
