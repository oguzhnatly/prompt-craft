import type { Env } from "./types";

const MINUTE_LIMIT = 60;
const DAY_LIMIT = 1000;
const MINUTE_TTL = 120; // 2 minutes (covers the current + previous window)
const DAY_TTL = 172800; // 48 hours (covers the current + previous day)

interface RateLimitResult {
  allowed: boolean;
  retryAfter?: number;
}

export async function checkRateLimit(
  licenseHash: string,
  env: Env
): Promise<RateLimitResult> {
  const now = Date.now();
  const minuteWindow = Math.floor(now / 60000);
  const dayWindow = new Date().toISOString().slice(0, 10); // YYYY-MM-DD

  const minuteKey = `rate:min:${licenseHash}:${minuteWindow}`;
  const dayKey = `rate:day:${licenseHash}:${dayWindow}`;

  const [minuteCount, dayCount] = await Promise.all([
    env.KV.get(minuteKey).then((v) => parseInt(v ?? "0", 10)),
    env.KV.get(dayKey).then((v) => parseInt(v ?? "0", 10)),
  ]);

  if (minuteCount >= MINUTE_LIMIT) {
    const secondsUntilNextMinute = 60 - Math.floor((now % 60000) / 1000);
    return { allowed: false, retryAfter: secondsUntilNextMinute };
  }

  if (dayCount >= DAY_LIMIT) {
    const midnight = new Date();
    midnight.setUTCHours(24, 0, 0, 0);
    const secondsUntilMidnight = Math.ceil(
      (midnight.getTime() - now) / 1000
    );
    return { allowed: false, retryAfter: secondsUntilMidnight };
  }

  return { allowed: true };
}

export async function incrementRateLimit(
  licenseHash: string,
  env: Env,
  ctx: ExecutionContext
): Promise<void> {
  const now = Date.now();
  const minuteWindow = Math.floor(now / 60000);
  const dayWindow = new Date().toISOString().slice(0, 10);

  const minuteKey = `rate:min:${licenseHash}:${minuteWindow}`;
  const dayKey = `rate:day:${licenseHash}:${dayWindow}`;

  // Fire-and-forget — don't block the response
  ctx.waitUntil(
    Promise.all([
      env.KV.get(minuteKey).then((v) => {
        const count = parseInt(v ?? "0", 10) + 1;
        return env.KV.put(minuteKey, count.toString(), {
          expirationTtl: MINUTE_TTL,
        });
      }),
      env.KV.get(dayKey).then((v) => {
        const count = parseInt(v ?? "0", 10) + 1;
        return env.KV.put(dayKey, count.toString(), {
          expirationTtl: DAY_TTL,
        });
      }),
    ])
  );
}
