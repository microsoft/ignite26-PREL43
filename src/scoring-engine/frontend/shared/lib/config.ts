export interface RuntimeConfig {
  app_name: string;
  auth_mode: "local" | "entra";
  entra: { tenant_id: string; client_id: string; api_scope: string };
  public_base_url: string;
  scorecard_base_url: string;
  graph_mode: "live" | "mock";
  environment: string;
}

let cached: RuntimeConfig | null = null;

export async function loadConfig(): Promise<RuntimeConfig> {
  if (cached) return cached;
  const res = await fetch("/api/config");
  if (!res.ok) throw new Error(`Could not load configuration (${res.status})`);
  cached = (await res.json()) as RuntimeConfig;
  return cached;
}

export function config(): RuntimeConfig {
  if (!cached) throw new Error("config not loaded");
  return cached;
}
