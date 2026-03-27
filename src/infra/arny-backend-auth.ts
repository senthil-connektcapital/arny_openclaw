import fs from "node:fs";
import path from "node:path";
import { resolveStateDir } from "../config/paths.js";

export const ARNY_BACKEND_AUTH_BASENAME = "arny-backend-auth.json";

export type ArnyBackendAuthFileV1 = {
  version: 1;
  email: string;
  accessToken: string;
  refreshToken?: string;
  updatedAt: string;
  backendBaseUrl: string;
};

export function resolveArnyBackendAuthPath(env: NodeJS.ProcessEnv = process.env): string {
  const override = env.OPENCLAW_ARNY_BACKEND_AUTH_FILE?.trim();
  if (override) {
    return path.resolve(override);
  }
  return path.join(resolveStateDir(env), ARNY_BACKEND_AUTH_BASENAME);
}

/**
 * Sync read for gateway heartbeat (no async on hot path).
 */
export function readArnyBackendAccessTokenSync(env: NodeJS.ProcessEnv = process.env): string {
  const p = resolveArnyBackendAuthPath(env);
  try {
    const raw = fs.readFileSync(p, "utf8");
    const parsed = JSON.parse(raw) as { accessToken?: unknown };
    const token = typeof parsed.accessToken === "string" ? parsed.accessToken.trim() : "";
    return token;
  } catch {
    return "";
  }
}

export async function writeArnyBackendAuth(params: {
  email: string;
  accessToken: string;
  refreshToken?: string;
  backendBaseUrl: string;
  env?: NodeJS.ProcessEnv;
}): Promise<string> {
  const env = params.env ?? process.env;
  const filePath = resolveArnyBackendAuthPath(env);
  const payload: ArnyBackendAuthFileV1 = {
    version: 1,
    email: params.email.trim(),
    accessToken: params.accessToken.trim(),
    ...(params.refreshToken ? { refreshToken: params.refreshToken.trim() } : {}),
    updatedAt: new Date().toISOString(),
    backendBaseUrl: params.backendBaseUrl.trim().replace(/\/+$/, ""),
  };
  await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
  await fs.promises.writeFile(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
  return filePath;
}
