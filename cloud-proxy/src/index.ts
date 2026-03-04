import type { Env, OptimizeRequest, ProxyError, AccessLog } from "./types";
import { validateLicense, hashLicenseKey } from "./license";
import { checkRateLimit, incrementRateLimit } from "./ratelimit";
import { resolveProvider, forwardToProvider } from "./providers";
import { normalizeStream } from "./stream";
import { handleStripeWebhook } from "./webhooks";
import { handleOllamaModels } from "./ollama-models";
import { handleClaudeModels } from "./claude-models";
import { handleOpenAIModels } from "./openai-models";
import { handleOpenRouterModels } from "./openrouter-models";

export default {
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext
  ): Promise<Response> {
    const url = new URL(request.url);

    // --- Health check ---
    if (url.pathname === "/health" && request.method === "GET") {
      return handleHealth(env);
    }

    // --- Stripe webhook ---
    if (url.pathname === "/webhooks/stripe" && request.method === "POST") {
      return handleStripeWebhook(request, env);
    }

    // --- Model list endpoints ---
    if (url.pathname === "/v1/ollama-models" && request.method === "GET") {
      return handleOllamaModels(env, ctx);
    }
    if (url.pathname === "/v1/claude-models" && request.method === "GET") {
      return handleClaudeModels(env, ctx);
    }
    if (url.pathname === "/v1/openai-models" && request.method === "GET") {
      return handleOpenAIModels(env, ctx);
    }
    if (url.pathname === "/v1/openrouter-models" && request.method === "GET") {
      return handleOpenRouterModels(env, ctx);
    }

    // --- Optimize endpoint ---
    if (url.pathname === "/v1/optimize" && request.method === "POST") {
      return handleOptimize(request, env, ctx);
    }

    return jsonError(404, "not_found", "Endpoint not found.");
  },
};

// ─── Health ─────────────────────────────────────────────────────────

function handleHealth(env: Env): Response {
  return Response.json({
    status: "ok",
    version: env.PROXY_VERSION ?? "1.0.0",
    providers: {
      claude: env.CLAUDE_API_KEY ? "configured" : "missing",
      deepseek: env.DEEPSEEK_API_KEY ? "configured" : "missing",
      openai: env.OPENAI_API_KEY ? "configured" : "missing",
    },
  });
}

// ─── Optimize ───────────────────────────────────────────────────────

async function handleOptimize(
  request: Request,
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  const startTime = Date.now();

  // 1. App identity check
  const appVersion = request.headers.get("X-PromptCraft-Version");
  if (!appVersion) {
    return jsonError(403, "forbidden", "Missing app identity header.");
  }

  // 2. Parse request body — content is NOT stored anywhere
  let body: OptimizeRequest;
  try {
    body = (await request.json()) as OptimizeRequest;
  } catch {
    return jsonError(400, "bad_request", "Invalid JSON body.");
  }

  if (!body.messages || !Array.isArray(body.messages) || body.messages.length === 0) {
    return jsonError(400, "bad_request", "Field 'messages' is required and must be non-empty.");
  }

  // 3. Extract license key (body field or Authorization header)
  const licenseKey =
    body.license_key ??
    extractBearerToken(request.headers.get("Authorization"));

  if (!licenseKey) {
    return jsonError(
      401,
      "unauthorized",
      "Missing license key. Provide it in the request body or Authorization header."
    );
  }

  // Remove license_key from body before forwarding — never send it to provider
  delete body.license_key;

  // 4. Validate license
  const licenseResult = await validateLicense(licenseKey, env);
  if (!licenseResult.valid) {
    return jsonError(
      403,
      "license_invalid",
      `Your license is not active. ${licenseResult.reason ?? ""} Please renew at https://promptcraft.app/checkout`
    );
  }

  // 5. Rate limiting
  const licenseHash = await hashLicenseKey(licenseKey);
  const rateResult = await checkRateLimit(licenseHash, env);
  if (!rateResult.allowed) {
    return jsonError(429, "rate_limited", "Rate limit exceeded. Please wait.", rateResult.retryAfter);
  }

  // Increment counters (non-blocking)
  incrementRateLimit(licenseHash, env, ctx);

  // 6. Resolve provider
  const resolved = resolveProvider(body, env);
  if (!resolved) {
    return jsonError(
      400,
      "invalid_provider",
      `Unknown or unconfigured provider: '${body.provider ?? body.model}'. Supported: claude, deepseek, openai.`
    );
  }

  // 7. Forward to provider
  let upstreamResponse: Response;
  try {
    upstreamResponse = await forwardToProvider(body, resolved);
  } catch {
    logAccess(ctx, env, {
      license_hash: licenseHash,
      timestamp: new Date().toISOString(),
      provider: resolved.providerName,
      model: resolved.resolvedModel,
      status: 502,
      latency_ms: Date.now() - startTime,
    });
    return jsonError(
      502,
      "provider_unavailable",
      "The AI provider is currently unavailable. Try again."
    );
  }

  // 8. Log access (status + latency only, NEVER content)
  logAccess(ctx, env, {
    license_hash: licenseHash,
    timestamp: new Date().toISOString(),
    provider: resolved.providerName,
    model: resolved.resolvedModel,
    status: upstreamResponse.status,
    latency_ms: Date.now() - startTime,
  });

  // 9. Handle upstream errors
  if (!upstreamResponse.ok) {
    // Forward error status without exposing raw provider error details.
    // Read the error but don't log the content.
    const statusCode = upstreamResponse.status;
    let errorMessage = `Provider returned ${statusCode}.`;

    try {
      const errBody = (await upstreamResponse.json()) as {
        error?: { message?: string; type?: string } | string;
      };
      const errObj = errBody.error;
      if (typeof errObj === "object" && errObj?.message) {
        errorMessage = errObj.message;
      } else if (typeof errObj === "string") {
        errorMessage = errObj;
      }
    } catch {
      // Provider returned non-JSON error — use generic message
    }

    return jsonError(statusCode, "provider_error", errorMessage);
  }

  // 10. Stream response back
  if (!upstreamResponse.body) {
    return jsonError(502, "provider_unavailable", "Provider returned empty response.");
  }

  const normalizedStream = normalizeStream(
    resolved.providerName,
    upstreamResponse.body
  );

  return new Response(normalizedStream, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}

// ─── Helpers ────────────────────────────────────────────────────────

function extractBearerToken(header: string | null): string | undefined {
  if (!header) return undefined;
  const parts = header.split(" ");
  if (parts.length === 2 && parts[0].toLowerCase() === "bearer") {
    return parts[1];
  }
  return undefined;
}

function jsonError(
  status: number,
  error: string,
  message: string,
  retryAfter?: number
): Response {
  const body: ProxyError = { error, message };
  if (retryAfter !== undefined) {
    body.retry_after = retryAfter;
  }

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (retryAfter !== undefined) {
    headers["Retry-After"] = retryAfter.toString();
  }

  return new Response(JSON.stringify(body), { status, headers });
}

function logAccess(
  ctx: ExecutionContext,
  _env: Env,
  log: AccessLog
): void {
  // Write to stdout only — Cloudflare Workers logs these via `console.log`.
  // ZERO content is included: only hash, timestamp, provider, model, status, latency.
  ctx.waitUntil(
    Promise.resolve().then(() => {
      console.log(JSON.stringify(log));
    })
  );
}
