export interface AccountBrokerConfiguration {
  AUTH_DB?: unknown;
  SESSION_ENCRYPTION_KEY?: string;
  AUTH_CALLBACK_ORIGIN?: string;
  AUTH_RETURN_URI_ALLOWLIST?: string;
}

export const DEFAULT_AUTH_RETURN_URIS = [
  "smartmovie://auth/callback",
  "https://smartmovie.app/auth/callback",
  "http://localhost:8080/auth/callback",
];

export function normalizedCallbackOrigin(value: string | undefined): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" && url.hostname !== "localhost") return null;
    return url.origin;
  } catch {
    return null;
  }
}

export function returnURIAllowed(value: string, env: AccountBrokerConfiguration): boolean {
  let candidate: URL;
  try {
    candidate = new URL(value);
  } catch {
    return false;
  }
  if (candidate.username || candidate.password || candidate.hash) return false;
  const allowed = (env.AUTH_RETURN_URI_ALLOWLIST?.split(",") ?? DEFAULT_AUTH_RETURN_URIS)
    .map((item) => item.trim())
    .filter(Boolean);
  return allowed.some((item) => {
    try {
      const expected = new URL(item);
      return expected.protocol === candidate.protocol
        && expected.host === candidate.host
        && expected.pathname === candidate.pathname;
    } catch {
      return false;
    }
  });
}

export function accountCapabilityReadiness(env: AccountBrokerConfiguration): {
  account: boolean;
  browserAuth: boolean;
  tvAuth: boolean;
} {
  const brokerConfigured = Boolean(
    env.AUTH_DB
      && env.SESSION_ENCRYPTION_KEY
      && env.SESSION_ENCRYPTION_KEY.length >= 32
      && normalizedCallbackOrigin(env.AUTH_CALLBACK_ORIGIN),
  );
  const nativeCallback = returnURIAllowed("smartmovie://auth/callback", env);
  const webCallback = returnURIAllowed("https://smartmovie.app/auth/callback", env)
    || returnURIAllowed("http://localhost:8080/auth/callback", env);
  const browserAuth = brokerConfigured && nativeCallback && webCallback;
  const tvAuth = brokerConfigured && nativeCallback;
  return { account: browserAuth || tvAuth, browserAuth, tvAuth };
}
