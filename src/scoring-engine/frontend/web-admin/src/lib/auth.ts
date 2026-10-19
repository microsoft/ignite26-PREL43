import { PublicClientApplication, InteractionRequiredAuthError, type AccountInfo } from "@azure/msal-browser";
import { config } from "@shared/lib/config";

const LOCAL_KEY = "vs_admin_token";
let msal: PublicClientApplication | null = null;

function storage(): Storage | null {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}

export async function initAuth(): Promise<void> {
  const cfg = config();
  if (cfg.auth_mode !== "entra") return;
  msal = new PublicClientApplication({
    auth: {
      clientId: cfg.entra.client_id,
      authority: `https://login.microsoftonline.com/${cfg.entra.tenant_id}`,
      redirectUri: window.location.origin + "/",
    },
    cache: { cacheLocation: "sessionStorage" },
  });
  await msal.initialize();
  const result = await msal.handleRedirectPromise();
  if (result?.account) msal.setActiveAccount(result.account);
  else if (!msal.getActiveAccount() && msal.getAllAccounts()[0]) msal.setActiveAccount(msal.getAllAccounts()[0]);
}

function account(): AccountInfo | null {
  return msal?.getActiveAccount() ?? null;
}

export function isSignedIn(): boolean {
  if (config().auth_mode === "entra") return account() !== null;
  return !!storage()?.getItem(LOCAL_KEY);
}

export async function getToken(): Promise<string | null> {
  if (config().auth_mode !== "entra") return storage()?.getItem(LOCAL_KEY) ?? null;
  const acct = account();
  if (!msal || !acct) return null;
  const scopes = [config().entra.api_scope];
  try {
    return (await msal.acquireTokenSilent({ scopes, account: acct })).accessToken;
  } catch (e) {
    if (e instanceof InteractionRequiredAuthError) await msal.acquireTokenRedirect({ scopes });
    throw e;
  }
}

export async function localLogin(username: string, password: string): Promise<void> {
  const res = await fetch("/api/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).detail ?? "Sign-in failed");
  storage()?.setItem(LOCAL_KEY, (await res.json()).access_token);
}

export async function entraLogin(): Promise<void> {
  await msal?.loginRedirect({ scopes: [config().entra.api_scope] });
}

export function signOut(): void {
  storage()?.removeItem(LOCAL_KEY);
  if (msal && account()) void msal.logoutRedirect({ postLogoutRedirectUri: window.location.origin + "/" });
  else window.location.href = "/login";
}

export function displayName(): string {
  return account()?.name ?? "Administrator";
}
