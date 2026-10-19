import { getToken, signOut } from "./auth";

export class ApiError extends Error {
  constructor(public status: number, message: string, public details?: string[]) {
    super(message);
  }
}

function describe(detail: unknown): { message: string; details?: string[] } {
  if (typeof detail === "string") return { message: detail };
  if (detail && typeof detail === "object") {
    const d = detail as { message?: string; errors?: unknown[]; error?: string };
    const details = (d.errors ?? []).map((e) =>
      typeof e === "string" ? e : `${(e as { field?: string }).field}: ${(e as { message?: string }).message}`,
    );
    return { message: d.message ?? d.error ?? "Request failed", details };
  }
  return { message: "Request failed" };
}

async function request<T>(method: string, path: string, body?: unknown, auth = true): Promise<T> {
  const headers: Record<string, string> = {};
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (auth) {
    const token = await getToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }
  const res = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  if (res.status === 401 && auth) {
    signOut();
    throw new ApiError(401, "Session expired");
  }
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    const { message, details } = describe(data.detail);
    throw new ApiError(res.status, message, details);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export const api = {
  get: <T>(path: string) => request<T>("GET", path),
  post: <T>(path: string, body?: unknown) => request<T>("POST", path, body ?? {}),
  patch: <T>(path: string, body: unknown) => request<T>("PATCH", path, body),
  del: (path: string) => request<void>("DELETE", path),
  public: <T>(path: string) => request<T>("GET", path, undefined, false),
};

export async function download(path: string): Promise<void> {
  const token = await getToken();
  const res = await fetch(path, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  if (!res.ok) throw new ApiError(res.status, "Export failed");
  const name = /filename="([^"]+)"/.exec(res.headers.get("Content-Disposition") ?? "")?.[1] ?? "export";
  const url = URL.createObjectURL(await res.blob());
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}
