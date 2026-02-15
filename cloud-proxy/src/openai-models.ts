import type { Env } from "./types";

const CACHE_KEY = "openai:models:v2";
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

// Known metadata for OpenAI chat models (the API doesn't return display names or context windows)
const OPENAI_MODEL_META: Record<
  string,
  { displayName: string; contextWindow: number; category: string; priority: number }
> = {
  // GPT-5.x family (latest)
  "gpt-5.3": { displayName: "GPT-5.3", contextWindow: 1_047_576, category: "flagship", priority: 1 },
  "gpt-5.3-mini": { displayName: "GPT-5.3 Mini", contextWindow: 1_047_576, category: "fast", priority: 2 },
  "gpt-5.2": { displayName: "GPT-5.2", contextWindow: 1_047_576, category: "flagship", priority: 3 },
  "gpt-5.2-mini": { displayName: "GPT-5.2 Mini", contextWindow: 1_047_576, category: "fast", priority: 4 },
  "gpt-5.2-pro": { displayName: "GPT-5.2 Pro", contextWindow: 1_047_576, category: "flagship", priority: 5 },
  "gpt-5.1": { displayName: "GPT-5.1", contextWindow: 1_047_576, category: "flagship", priority: 6 },
  "gpt-5": { displayName: "GPT-5", contextWindow: 1_047_576, category: "flagship", priority: 7 },
  "gpt-5-mini": { displayName: "GPT-5 Mini", contextWindow: 1_047_576, category: "fast", priority: 8 },
  "gpt-5-nano": { displayName: "GPT-5 Nano", contextWindow: 1_047_576, category: "fast", priority: 9 },
  // GPT-4.1 family
  "gpt-4.1": { displayName: "GPT-4.1", contextWindow: 1_047_576, category: "balanced", priority: 10 },
  "gpt-4.1-mini": { displayName: "GPT-4.1 Mini", contextWindow: 1_047_576, category: "fast", priority: 11 },
  "gpt-4.1-nano": { displayName: "GPT-4.1 Nano", contextWindow: 1_047_576, category: "fast", priority: 12 },
  // GPT-4o family
  "gpt-4o": { displayName: "GPT-4o", contextWindow: 128_000, category: "balanced", priority: 15 },
  "gpt-4o-mini": { displayName: "GPT-4o Mini", contextWindow: 128_000, category: "fast", priority: 16 },
  // o-series reasoning (latest first)
  "o4-mini": { displayName: "o4 Mini", contextWindow: 200_000, category: "reasoning", priority: 20 },
  "o3": { displayName: "o3", contextWindow: 200_000, category: "reasoning", priority: 21 },
  "o3-pro": { displayName: "o3 Pro", contextWindow: 200_000, category: "reasoning", priority: 22 },
  "o3-mini": { displayName: "o3 Mini", contextWindow: 200_000, category: "reasoning", priority: 23 },
  "o1": { displayName: "o1", contextWindow: 200_000, category: "reasoning", priority: 25 },
};

// Prefixes that identify chat-capable models
const CHAT_MODEL_PREFIXES = ["gpt-5", "gpt-4", "o1", "o3", "o4"];

// Models to exclude
const EXCLUDE_PATTERNS = [
  /^ft:/,                   // fine-tuned
  /-\d{4}-\d{2}-\d{2}$/,   // dated snapshots like gpt-4o-2024-08-06
  /-\d{4}$/,                // dated like gpt-3.5-turbo-0125
  /audio/i,
  /realtime/i,
  /search/i,
  /instruct/i,
  /vision/i,
  /embed/i,
  /tts/i,
  /whisper/i,
  /dall-e/i,
  /davinci/i,
  /babbage/i,
  /curie/i,
  /ada/i,
  /moderation/i,
  /omni-moderation/i,
  /chatgpt/i,               // chatgpt-* aliases
  /transcribe/i,
  /diarize/i,
  /preview/i,
  /16k$/,
  /^gpt-4-0/,               // dated gpt-4 snapshots
  /^gpt-3/,                 // all gpt-3.x models (too old)
  /^gpt-4-turbo$/,          // old gpt-4-turbo
  /^gpt-4$/,                // old base gpt-4
  /codex/i,                 // codex variants (code-only)
  /chat-latest/i,           // unstable "latest" aliases
];

export async function handleOpenAIModels(
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

  // 2. Fetch from OpenAI API
  let models: CloudModelInfo[];
  try {
    models = await fetchOpenAIModels(env);
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

// ─── OpenAI API ──────────────────────────────────────────────────

interface OpenAIModel {
  id: string;
  object: string;
  created: number;
  owned_by: string;
}

interface OpenAIModelsResponse {
  data: OpenAIModel[];
}

async function fetchOpenAIModels(env: Env): Promise<CloudModelInfo[]> {
  if (!env.OPENAI_API_KEY) throw new Error("OPENAI_API_KEY not configured");

  const response = await fetch("https://api.openai.com/v1/models", {
    headers: {
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
    },
  });

  if (!response.ok) throw new Error(`OpenAI API returned ${response.status}`);

  const body = (await response.json()) as OpenAIModelsResponse;
  return processOpenAIModels(body.data);
}

function processOpenAIModels(apiModels: OpenAIModel[]): CloudModelInfo[] {
  const chatModels = apiModels.filter((m) => {
    const matchesPrefix = CHAT_MODEL_PREFIXES.some((p) => m.id.startsWith(p));
    if (!matchesPrefix) return false;
    return !EXCLUDE_PATTERNS.some((p) => p.test(m.id));
  });

  const seen = new Set<string>();
  const results: CloudModelInfo[] = [];

  // First pass: known models from our metadata that exist in the API
  const apiIds = new Set(chatModels.map((m) => m.id));
  const sortedMeta = Object.entries(OPENAI_MODEL_META).sort((a, b) => a[1].priority - b[1].priority);

  for (const [id, meta] of sortedMeta) {
    if (apiIds.has(id)) {
      results.push({
        id,
        displayName: meta.displayName,
        contextWindow: meta.contextWindow,
        isDefault: results.length === 0,
        category: meta.category,
      });
      seen.add(id);
    }
  }

  // Second pass: any new models from API we don't know about yet (newest first)
  const remaining = chatModels
    .filter((m) => !seen.has(m.id))
    .sort((a, b) => b.created - a.created);

  for (const model of remaining) {
    results.push({
      id: model.id,
      displayName: formatModelName(model.id),
      contextWindow: guessContextWindow(model.id),
      isDefault: results.length === 0,
      category: guessCategory(model.id),
    });
  }

  return results;
}

function formatModelName(id: string): string {
  return id
    .split("-")
    .map((p) => {
      if (p === "gpt") return "GPT";
      if (p === "4o") return "4o";
      if (/^\d/.test(p)) return p;
      return p.charAt(0).toUpperCase() + p.slice(1);
    })
    .join(" ")
    .replace("GPT 5.3", "GPT-5.3")
    .replace("GPT 5.2", "GPT-5.2")
    .replace("GPT 5", "GPT-5")
    .replace("GPT 4o", "GPT-4o")
    .replace("GPT 4.1", "GPT-4.1");
}

function guessContextWindow(id: string): number {
  if (id.includes("5.") || id.includes("4.1")) return 1_047_576;
  if (id.startsWith("o")) return 200_000;
  return 128_000;
}

function guessCategory(id: string): string {
  if (id.startsWith("o")) return "reasoning";
  if (id.includes("mini") || id.includes("nano")) return "fast";
  return "flagship";
}

// ─── Fallback ────────────────────────────────────────────────────

const FALLBACK_MODELS: CloudModelInfo[] = [
  { id: "gpt-4.1", displayName: "GPT-4.1", contextWindow: 1_047_576, isDefault: true, category: "flagship" },
  { id: "gpt-4.1-mini", displayName: "GPT-4.1 Mini", contextWindow: 1_047_576, isDefault: false, category: "fast" },
  { id: "gpt-4.1-nano", displayName: "GPT-4.1 Nano", contextWindow: 1_047_576, isDefault: false, category: "fast" },
  { id: "gpt-4o", displayName: "GPT-4o", contextWindow: 128_000, isDefault: false, category: "balanced" },
  { id: "gpt-4o-mini", displayName: "GPT-4o Mini", contextWindow: 128_000, isDefault: false, category: "fast" },
  { id: "o4-mini", displayName: "o4 Mini", contextWindow: 200_000, isDefault: false, category: "reasoning" },
  { id: "o3", displayName: "o3", contextWindow: 200_000, isDefault: false, category: "reasoning" },
  { id: "o3-mini", displayName: "o3 Mini", contextWindow: 200_000, isDefault: false, category: "reasoning" },
];
