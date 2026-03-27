import { createSubsystemLogger } from "../logging/subsystem.js";
import { readArnyBackendAccessTokenSync } from "./arny-backend-auth.js";

const log = createSubsystemLogger("gateway/backend-gateway-heartbeat");

const DEFAULT_BACKEND_URL = "http://localhost:8000";
const DEFAULT_INTERVAL_MS = 15 * 60 * 1000;

type TimerEntry = {
  timer: NodeJS.Timeout;
};

const timersByAccessToken = new Map<string, TimerEntry>();

function resolveBackendAccessToken(): string {
  const fromEnv = (
    process.env.OPENCLAW_ARNY_BACKEND_ACCESS_TOKEN ??
    process.env.OPENCLAW_ARNY_BACKEND_TOKEN ??
    ""
  ).trim();
  if (fromEnv) {
    return fromEnv;
  }
  return readArnyBackendAccessTokenSync();
}

function resolveBackendUrl(): string {
  return (process.env.OPENCLAW_ARNY_BACKEND_URL ?? DEFAULT_BACKEND_URL).trim().replace(/\/+$/, "");
}

function resolveHeartbeatIntervalMs(): number {
  const raw = (process.env.OPENCLAW_ARNY_GATEWAY_HEARTBEAT_INTERVAL_MS ?? "").trim();
  if (!raw) {
    return DEFAULT_INTERVAL_MS;
  }
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_INTERVAL_MS;
  }
  return parsed;
}

/**
 * POST /openclaw/gateway/heartbeat. Returns true when the backend accepts the heartbeat.
 */
export async function sendHeartbeatOnce(params: {
  gatewayUrl: string;
  backendUrl: string;
  accessToken: string;
  gatewayToken?: string;
  gatewayPassword?: string;
}): Promise<boolean> {
  const { gatewayUrl, backendUrl, accessToken, gatewayToken, gatewayPassword } = params;
  const gatewayUrlResolved = (gatewayUrl || "").trim();
  if (!gatewayUrlResolved) {
    return false;
  }

  const body: Record<string, string> = { gateway_url: gatewayUrlResolved };
  const token = (gatewayToken ?? "").trim();
  const password = (gatewayPassword ?? "").trim();
  if (token) {
    body.gateway_token = token;
  }
  if (password) {
    body.gateway_password = password;
  }

  const res = await fetch(`${backendUrl}/openclaw/gateway/heartbeat`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    log.warn(`heartbeat failed: ${res.status} ${txt.slice(0, 200)}`);
    return false;
  }
  return true;
}

export function ensureBackendGatewayHeartbeat(params: {
  gatewayUrl: string;
  gatewayToken?: string;
  gatewayPassword?: string;
}) {
  const accessToken = resolveBackendAccessToken();
  const backendUrl = resolveBackendUrl();
  const intervalMs = resolveHeartbeatIntervalMs();
  if (!accessToken) {
    log.warn(
      `heartbeat not started: set env OPENCLAW_ARNY_BACKEND_ACCESS_TOKEN or run openclaw signin`,
    );
    return;
  }

  // Ensure we don't create multiple intervals for the same token.
  if (timersByAccessToken.has(accessToken)) {
    // Still fire a quick immediate update with the newest gatewayUrl.
    void sendHeartbeatOnce({
      gatewayUrl: params.gatewayUrl,
      backendUrl,
      accessToken,
      gatewayToken: params.gatewayToken,
      gatewayPassword: params.gatewayPassword,
    }).catch(() => {
      /* ignore */
    });
    return;
  }

  void sendHeartbeatOnce({
    gatewayUrl: params.gatewayUrl,
    backendUrl,
    accessToken,
    gatewayToken: params.gatewayToken,
    gatewayPassword: params.gatewayPassword,
  }).catch(() => {
    /* ignore */
  });

  const timer = setInterval(() => {
    void sendHeartbeatOnce({
      gatewayUrl: params.gatewayUrl,
      backendUrl,
      accessToken,
      gatewayToken: params.gatewayToken,
      gatewayPassword: params.gatewayPassword,
    }).catch(() => {
      /* ignore */
    });
  }, intervalMs);

  timersByAccessToken.set(accessToken, { timer });
}
