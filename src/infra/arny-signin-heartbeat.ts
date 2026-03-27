import { loadConfig } from "../config/io.js";
import { resolveGatewayPort } from "../config/paths.js";

/**
 * WebSocket URL this machine's gateway listens on, for backend registry.
 * Override with OPENCLAW_GATEWAY_WS_URL when using a tunnel or non-loopback URL.
 */
export function resolveGatewayWsUrlForArnyBackendHeartbeat(
  env: NodeJS.ProcessEnv = process.env,
): string {
  const raw = env.OPENCLAW_GATEWAY_WS_URL?.trim();
  if (raw) {
    return raw.replace(/\/+$/, "");
  }
  const cfg = loadConfig();
  const port = resolveGatewayPort(cfg, env);
  return `ws://127.0.0.1:${port}`;
}

/**
 * Gateway websocket shared credentials from config (same source as gateway heartbeat after operator connect).
 */
export function resolveGatewayAuthForArnyBackendHeartbeat(): {
  gatewayToken?: string;
  gatewayPassword?: string;
} {
  const cfg = loadConfig();
  const mode = cfg.gateway?.auth?.mode;
  const tokenRaw = cfg.gateway?.auth?.token;
  const passwordRaw = cfg.gateway?.auth?.password;
  const token = typeof tokenRaw === "string" ? tokenRaw.trim() : "";
  const password = typeof passwordRaw === "string" ? passwordRaw.trim() : "";
  if (mode === "password") {
    return password ? { gatewayPassword: password } : {};
  }
  if (mode === "token" || mode === undefined) {
    return token ? { gatewayToken: token } : {};
  }
  return {};
}
