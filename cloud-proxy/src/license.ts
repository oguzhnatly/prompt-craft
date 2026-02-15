import type { Env } from "./types";

const CACHE_TTL_SECONDS = 86400; // 24 hours
const INVALID_CACHE_TTL_SECONDS = 3600; // 1 hour

export async function hashLicenseKey(key: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(key);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

interface KeygenValidateResponse {
  meta: {
    valid: boolean;
    detail: string;
    code: string;
  };
  data?: {
    id: string;
    attributes: {
      metadata?: Record<string, string>;
    };
  };
}

export async function validateLicense(
  licenseKey: string,
  env: Env
): Promise<{ valid: boolean; tier?: string; reason?: string }> {
  const hash = await hashLicenseKey(licenseKey);
  const cacheKey = `license:${hash}`;

  // Check cache first
  const cached = await env.KV.get(cacheKey);
  if (cached) {
    try {
      const parsed = JSON.parse(cached) as {
        valid: boolean;
        tier?: string;
      };
      if (parsed.valid) {
        return { valid: true, tier: parsed.tier };
      }
      return { valid: false, reason: "License is not active." };
    } catch {
      // Corrupted cache — fall through to validation
    }
  }

  // Validate against Keygen.sh
  try {
    const response = await fetch(
      `https://api.keygen.sh/v1/accounts/${env.KEYGEN_ACCOUNT_ID}/licenses/actions/validate`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/vnd.api+json",
          Accept: "application/vnd.api+json",
          Authorization: `Bearer ${env.KEYGEN_PRODUCT_TOKEN}`,
        },
        body: JSON.stringify({
          meta: {
            key: licenseKey,
          },
        }),
      }
    );

    if (!response.ok && response.status >= 500) {
      // Keygen API error — don't cache, allow retry
      return { valid: false, reason: "License validation service unavailable." };
    }

    const data = (await response.json()) as KeygenValidateResponse;
    const code = data.meta.code;

    // Proxy only checks key validity — machine activation is client-side
    if (code === "VALID" || code === "NO_MACHINE" || code === "NO_MACHINES") {
      const tier = data.data?.attributes?.metadata?.["tier"] ?? "pro";
      await env.KV.put(
        cacheKey,
        JSON.stringify({ valid: true, tier }),
        { expirationTtl: CACHE_TTL_SECONDS }
      );
      return { valid: true, tier };
    }

    // Cache invalid result for a shorter period to allow re-validation
    await env.KV.put(
      cacheKey,
      JSON.stringify({ valid: false }),
      { expirationTtl: INVALID_CACHE_TTL_SECONDS }
    );
    return {
      valid: false,
      reason: `License status: ${code}.`,
    };
  } catch {
    // Network error — don't cache, don't block user
    return { valid: false, reason: "Unable to validate license. Try again." };
  }
}
