import type { Command } from "commander";
import { writeArnyBackendAuth } from "../../infra/arny-backend-auth.js";
import {
  resolveGatewayAuthForArnyBackendHeartbeat,
  resolveGatewayWsUrlForArnyBackendHeartbeat,
} from "../../infra/arny-signin-heartbeat.js";
import { sendHeartbeatOnce } from "../../infra/backend-gateway-heartbeat.js";
import { defaultRuntime } from "../../runtime.js";
import { theme } from "../../terminal/theme.js";
import { runCommandWithRuntime } from "../cli-utils.js";

type SigninOpts = {
  email: string;
  password: string;
  baseUrl?: string;
  printToken?: boolean;
};

async function runArnySignin(opts: SigninOpts): Promise<void> {
  const baseUrl = (opts.baseUrl ?? "http://localhost:8000").trim().replace(/\/+$/, "");
  const url = `${baseUrl}/auth/signin`;
  const body = {
    action: "signin",
    email: opts.email.trim(),
    password: opts.password,
  };

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const text = await res.text();
  let parsed: unknown;
  try {
    parsed = JSON.parse(text) as unknown;
  } catch {
    defaultRuntime.error(`signin failed: invalid JSON (${res.status})`);
    defaultRuntime.error(text.slice(0, 500));
    process.exitCode = 1;
    return;
  }

  if (!res.ok) {
    defaultRuntime.error(`signin failed: HTTP ${res.status}`);
    defaultRuntime.error(text.slice(0, 500));
    process.exitCode = 1;
    return;
  }

  const root = parsed as {
    success?: boolean;
    data?: { session?: { access_token?: string; refresh_token?: string } };
  };
  const accessToken = root.data?.session?.access_token?.trim() ?? "";
  const refreshToken = root.data?.session?.refresh_token?.trim();

  if (!accessToken) {
    defaultRuntime.error("signin response missing data.session.access_token");
    process.exitCode = 1;
    return;
  }

  const filePath = await writeArnyBackendAuth({
    email: opts.email,
    accessToken,
    refreshToken,
    backendBaseUrl: baseUrl,
  });

  const gatewayUrl = resolveGatewayWsUrlForArnyBackendHeartbeat();
  const gwAuth = resolveGatewayAuthForArnyBackendHeartbeat();
  const heartbeatOk = await sendHeartbeatOnce({
    gatewayUrl,
    backendUrl: baseUrl,
    accessToken,
    gatewayToken: gwAuth.gatewayToken,
    gatewayPassword: gwAuth.gatewayPassword,
  });

  if (opts.printToken) {
    defaultRuntime.writeStdout(`${accessToken}\n`);
    return;
  }

  defaultRuntime.log(
    `${theme.success("Signed in to Arny backend")} — token saved to ${theme.muted(filePath)}`,
  );
  if (heartbeatOk) {
    defaultRuntime.log(theme.muted("Arny backend gateway registry heartbeat accepted"));
  } else {
    defaultRuntime.log(
      theme.warn(
        "Gateway registry heartbeat failed; submit may report machine not registered until the gateway runs",
      ),
    );
  }
}

export function registerSigninCommand(program: Command) {
  program
    .command("signin")
    .description(
      "Sign in to Arny backend (Supabase JWT), save token, and send an initial gateway registry heartbeat",
    )
    .requiredOption("--email <email>", "Arny account email")
    .requiredOption("--password <password>", "Arny account password")
    .option(
      "--base-url <url>",
      "Arny backend base URL",
      process.env.OPENCLAW_ARNY_BACKEND_URL ?? "http://localhost:8000",
    )
    .option("--print-token", "Print access token to stdout only (for scripts)", false)
    .action(
      async (opts: { email: string; password: string; baseUrl?: string; printToken?: boolean }) => {
        await runCommandWithRuntime(defaultRuntime, async () => {
          await runArnySignin({
            email: opts.email,
            password: opts.password,
            baseUrl: opts.baseUrl,
            printToken: Boolean(opts.printToken),
          });
        });
      },
    );
}
