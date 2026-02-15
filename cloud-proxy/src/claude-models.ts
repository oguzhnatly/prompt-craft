import type { Env } from "./types";

const CACHE_KEY = "claude:models:v1";
const CACHE_TTL = 3600; // 1 hour

export interface CloudModelInfo {
  id: string;
  displayName: string;
  contextWindow: number;
  isDefault: boolean;
  category: string; // "flagship" | "balanced" | "fast" | "reasoning"
}

interface CachedModels {
  models: CloudModelInfo[];
  fetchedAt: string;
}

// Known context windows and display names for Claude models
// Only include 4.6, 4.5, 4.x, and 3.5 — nothing older
const CLAUDE_MODEL_META: Record<
  string,
  { displayName: string; contextWindow: number; category: string; priority: number }
> = {
  "claude-opus-4-6": { displayName: "Claude Opus 4.6", contextWindow: 200_000, category: "flagship", priority: 1 },
  "claude-opus-4-5": { displayName: "Claude Opus 4.5", contextWindow: 200_000, category: "flagship", priority: 2 },
  "claude-sonnet-4-5": { displayName: "Claude Sonnet 4.5", contextWindow: 200_000, category: "balanced", priority: 3 },
  "claude-haiku-4-5": { displayName: "Claude Haiku 4.5", contextWindow: 200_000, category: "fast", priority: 4 },
  "claude-opus-4-1": { displayName: "Claude Opus 4.1", contextWindow: 200_000, category: "flagship", priority: 5 },
  "claude-opus-4": { displayName: "Claude Opus 4", contextWindow: 200_000, category: "flagship", priority: 6 },
  "claude-sonnet-4": { displayName: "Claude Sonnet 4", contextWindow: 200_000, category: "balanced", priority: 7 },
  "claude-3-5-sonnet": { displayName: "Claude 3.5 Sonnet", contextWindow: 200_000, category: "balanced", priority: 10 },
  "claude-3-5-haiku": { displayName: "Claude 3.5 Haiku", contextWindow: 200_000, category: "fast", priority: 11 },
};

// Model families older than 3.5 are excluded entirely
const MIN_ALLOWED_FAMILIES = new Set([
  "claude-opus-4-6",
  "claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5",
  "claude-opus-4-1",
  "claude-opus-4", "claude-sonnet-4",
  "claude-3-5-sonnet", "claude-3-5-haiku",
]);

export async function handleClaudeModels(
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  // 1. Try KV cache first
  const cached = (await env.KV.get(CACHE_KEY, "json")) as CachedModels | null;
  if (cached && cached.models.length > 0) {
    return Response.json(
      { models: cached.models, source: "cache", fetchedAt: cached.fetchedAt },
      { headers: { "Cache-Control": "public, max-age=600", "Access-Control-Allow-Origin": "*" } }
    );
  }

  // 2. Fetch from Anthropic API
  let models: CloudModelInfo[];
  try {
    models = await fetchAnthropicModels(env);
  } catch {
    if (cached) {
      return Response.json(
        { models: cached.models, source: "stale-cache", fetchedAt: cached.fetchedAt },
        { headers: { "Access-Control-Allow-Origin": "*" } }
      );
    }
    return Response.json(
      { models: FALLBACK_MODELS, source: "fallback", fetchedAt: new Date().toISOString() },
      { headers: { "Access-Control-Allow-Origin": "*" } }
    );
  }

  if (models.length === 0) {
    return Response.json(
      { models: FALLBACK_MODELS, source: "fallback", fetchedAt: new Date().toISOString() },
      { headers: { "Access-Control-Allow-Origin": "*" } }
    );
  }

  // 3. Store in KV (non-blocking)
  const cacheData: CachedModels = { models, fetchedAt: new Date().toISOString() };
  ctx.waitUntil(
    env.KV.put(CACHE_KEY, JSON.stringify(cacheData), { expirationTtl: CACHE_TTL })
  );

  return Response.json(
    { models, source: "live", fetchedAt: cacheData.fetchedAt },
    { headers: { "Cache-Control": "public, max-age=600", "Access-Control-Allow-Origin": "*" } }
  );
}

// ─── Anthropic API ───────────────────────────────────────────────

interface AnthropicModel {
  id: string;
  display_name: string;
  created_at: string;
  type: string;
}

interface AnthropicModelsResponse {
  data: AnthropicModel[];
  has_more: boolean;
  first_id?: string;
  last_id?: string;
}

async function fetchAnthropicModels(env: Env): Promise<CloudModelInfo[]> {
  if (!env.CLAUDE_API_KEY) throw new Error("CLAUDE_API_KEY not configured");

  const allModels: AnthropicModel[] = [];
  let afterId: string | undefined;

  // Paginate through all models
  for (let page = 0; page < 5; page++) {
    const url = new URL("https://api.anthropic.com/v1/models");
    url.searchParams.set("limit", "100");
    if (afterId) url.searchParams.set("after_id", afterId);

    const response = await fetch(url.toString(), {
      headers: {
        "x-api-key": env.CLAUDE_API_KEY,
        "anthropic-version": "2023-06-01",
      },
    });

    if (!response.ok) throw new Error(`Anthropic API returned ${response.status}`);

    const body = (await response.json()) as AnthropicModelsResponse;
    allModels.push(...body.data);

    if (!body.has_more) break;
    afterId = body.last_id;
  }

  return processAnthropicModels(allModels);
}

function processAnthropicModels(apiModels: AnthropicModel[]): CloudModelInfo[] {
  // Group by model family — pick the latest dated version for each base name
  const familyMap = new Map<string, { model: AnthropicModel; date: string }>();

  for (const model of apiModels) {
    if (!model.id.startsWith("claude-")) continue;

    const baseName = extractBaseName(model.id);
    if (!baseName) continue;

    // Skip old model families (claude-3-opus, claude-3-sonnet, claude-3-haiku, etc.)
    // Only allow known families or any new 4.x+ / 5.x+ models
    const isKnownAllowed = MIN_ALLOWED_FAMILIES.has(baseName);
    const isNewGeneration = /^claude-(opus|sonnet|haiku)-[4-9]/.test(baseName);
    if (!isKnownAllowed && !isNewGeneration) continue;

    const dateStr = extractDateSuffix(model.id);
    const existing = familyMap.get(baseName);

    if (!existing || dateStr > existing.date) {
      familyMap.set(baseName, { model, date: dateStr });
    }
  }

  // Convert to CloudModelInfo
  const results: CloudModelInfo[] = [];
  let isFirst = true;

  // Sort by priority (known models first, then alphabetical)
  const sorted = [...familyMap.entries()].sort((a, b) => {
    const pa = CLAUDE_MODEL_META[a[0]]?.priority ?? 50;
    const pb = CLAUDE_MODEL_META[b[0]]?.priority ?? 50;
    return pa - pb;
  });

  for (const [baseName, { model }] of sorted) {
    const meta = CLAUDE_MODEL_META[baseName];

    results.push({
      id: model.id,
      displayName: meta?.displayName ?? model.display_name ?? formatModelName(model.id),
      contextWindow: meta?.contextWindow ?? 200_000,
      isDefault: isFirst,
      category: meta?.category ?? "balanced",
    });
    isFirst = false;
  }

  return results;
}

function extractBaseName(modelId: string): string | null {
  // "claude-sonnet-4-5-20250929" → "claude-sonnet-4-5"
  // "claude-3-5-sonnet-20241022" → "claude-3-5-sonnet"
  const dateMatch = modelId.match(/^(.+)-(\d{8})$/);
  if (dateMatch) return dateMatch[1];
  // No date suffix — use as-is (e.g. "claude-3-opus-latest")
  if (modelId.includes("latest")) return null; // Skip "latest" aliases
  return modelId;
}

function extractDateSuffix(modelId: string): string {
  const match = modelId.match(/-(\d{8})$/);
  return match?.[1] ?? "00000000";
}

function formatModelName(id: string): string {
  return id
    .replace(/-\d{8}$/, "")
    .split("-")
    .map((p) => p.charAt(0).toUpperCase() + p.slice(1))
    .join(" ");
}

// ─── Fallback ────────────────────────────────────────────────────

const FALLBACK_MODELS: CloudModelInfo[] = [
  { id: "claude-opus-4-6-20250916", displayName: "Claude Opus 4.6", contextWindow: 200_000, isDefault: true, category: "flagship" },
  { id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5", contextWindow: 200_000, isDefault: false, category: "balanced" },
  { id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5", contextWindow: 200_000, isDefault: false, category: "fast" },
  { id: "claude-3-5-sonnet-20241022", displayName: "Claude 3.5 Sonnet", contextWindow: 200_000, isDefault: false, category: "balanced" },
  { id: "claude-3-5-haiku-20241022", displayName: "Claude 3.5 Haiku", contextWindow: 200_000, isDefault: false, category: "fast" },
];
