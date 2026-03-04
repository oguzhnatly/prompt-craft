import type { Env } from "./types";

const CACHE_KEY = "openrouter:models:v1";
const CACHE_TTL = 1800; // 30 minutes

export interface OpenRouterModel {
  id: string;
  displayName: string;
  description: string;
  contextLength: number;
  provider: string;
  isFree: boolean;
  pricing: {
    promptPer1k: number;
    completionPer1k: number;
  };
}

interface CachedModels {
  models: OpenRouterModel[];
  fetchedAt: string;
}

export async function handleOpenRouterModels(
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  const headers = {
    "Cache-Control": "public, max-age=300",
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json",
  };

  // 1. Try KV cache first
  const cached = await env.KV.get(CACHE_KEY, "json") as CachedModels | null;
  if (cached && cached.models.length > 0) {
    return Response.json(
      { models: cached.models, source: "cache", fetchedAt: cached.fetchedAt },
      { headers }
    );
  }

  // 2. Fetch live from OpenRouter (public endpoint — no auth required)
  let models: OpenRouterModel[];
  try {
    models = await fetchOpenRouterModels();
  } catch (err) {
    if (cached) {
      return Response.json(
        { models: cached.models, source: "stale-cache", fetchedAt: cached.fetchedAt },
        { headers }
      );
    }
    return Response.json(
      { models: FALLBACK_MODELS, source: "fallback", fetchedAt: new Date().toISOString() },
      { headers }
    );
  }

  if (models.length === 0) {
    return Response.json(
      { models: FALLBACK_MODELS, source: "fallback", fetchedAt: new Date().toISOString() },
      { headers }
    );
  }

  // 3. Cache in KV (non-blocking)
  const cacheData: CachedModels = { models, fetchedAt: new Date().toISOString() };
  ctx.waitUntil(
    env.KV.put(CACHE_KEY, JSON.stringify(cacheData), { expirationTtl: CACHE_TTL })
  );

  return Response.json(
    { models, source: "live", fetchedAt: cacheData.fetchedAt },
    { headers }
  );
}

async function fetchOpenRouterModels(): Promise<OpenRouterModel[]> {
  const response = await fetch("https://openrouter.ai/api/v1/models", {
    headers: { "User-Agent": "PromptCraft-CloudProxy/1.0" },
    cf: { cacheTtl: 300 },
  });

  if (!response.ok) {
    throw new Error(`OpenRouter API returned ${response.status}`);
  }

  const json = (await response.json()) as {
    data: Array<{
      id: string;
      name: string;
      description?: string;
      context_length?: number;
      pricing?: { prompt?: string; completion?: string };
    }>;
  };

  const models = json.data
    .filter((m) => isUsableModel(m.id))
    .slice(0, 100)
    .map((m): OpenRouterModel => {
      const promptPrice = parseFloat(m.pricing?.prompt ?? "0");
      const completionPrice = parseFloat(m.pricing?.completion ?? "0");
      return {
        id: m.id,
        displayName: m.name ?? formatModelId(m.id),
        description: (m.description ?? "").slice(0, 150),
        contextLength: m.context_length ?? 8192,
        provider: extractProvider(m.id),
        isFree: promptPrice === 0 && completionPrice === 0,
        pricing: {
          promptPer1k: promptPrice * 1000,
          completionPer1k: completionPrice * 1000,
        },
      };
    });

  return models;
}

function isUsableModel(id: string): boolean {
  const blocked = ["dall-e", "whisper", "tts", "embed", "moderation", "vision-only"];
  return !blocked.some((b) => id.toLowerCase().includes(b));
}

function extractProvider(id: string): string {
  const slash = id.indexOf("/");
  if (slash === -1) return "unknown";
  const raw = id.slice(0, slash);
  const map: Record<string, string> = {
    "anthropic": "Anthropic",
    "openai": "OpenAI",
    "meta-llama": "Meta",
    "google": "Google",
    "deepseek": "DeepSeek",
    "mistralai": "Mistral",
    "x-ai": "xAI",
    "moonshotai": "Moonshot",
    "minimax": "MiniMax",
    "thudm": "Zhipu",
    "arcee-ai": "Arcee",
    "qwen": "Alibaba",
    "cohere": "Cohere",
    "nousresearch": "Nous Research",
  };
  return map[raw] ?? raw;
}

function formatModelId(id: string): string {
  const name = id.includes("/") ? id.split("/")[1] : id;
  return name
    .replace(/-/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .replace(/\bLlama\b/g, "Llama")
    .replace(/\bGpt\b/g, "GPT")
    .replace(/\bGemini\b/g, "Gemini");
}

// ─── Fallback curated list ────────────────────────────────────────

const FALLBACK_MODELS: OpenRouterModel[] = [
  { id: "deepseek/deepseek-chat-v3-0324", displayName: "DeepSeek V3", description: "Latest DeepSeek V3 model.", contextLength: 163840, provider: "DeepSeek", isFree: false, pricing: { promptPer1k: 0.27, completionPer1k: 1.1 } },
  { id: "meta-llama/llama-4-maverick", displayName: "Llama 4 Maverick", description: "Meta's Llama 4 Maverick model.", contextLength: 1048576, provider: "Meta", isFree: false, pricing: { promptPer1k: 0.17, completionPer1k: 0.6 } },
  { id: "google/gemini-2.5-pro-preview", displayName: "Gemini 2.5 Pro", description: "Google's most capable Gemini model.", contextLength: 1048576, provider: "Google", isFree: false, pricing: { promptPer1k: 1.25, completionPer1k: 10 } },
  { id: "mistralai/mistral-large-2411", displayName: "Mistral Large", description: "Mistral's flagship model.", contextLength: 131072, provider: "Mistral", isFree: false, pricing: { promptPer1k: 2, completionPer1k: 6 } },
  { id: "x-ai/grok-3-beta", displayName: "Grok 3 Beta", description: "xAI's Grok 3 model.", contextLength: 131072, provider: "xAI", isFree: false, pricing: { promptPer1k: 3, completionPer1k: 15 } },
  { id: "minimax/minimax-m1", displayName: "MiniMax M1", description: "MiniMax's flagship model with 1M context.", contextLength: 1000000, provider: "MiniMax", isFree: false, pricing: { promptPer1k: 0.3, completionPer1k: 1.1 } },
  { id: "moonshotai/kimi-k2", displayName: "Kimi K2", description: "Moonshot AI's Kimi K2 model.", contextLength: 131072, provider: "Moonshot", isFree: false, pricing: { promptPer1k: 0.06, completionPer1k: 2.5 } },
  { id: "qwen/qwen3-235b-a22b", displayName: "Qwen 3 235B", description: "Alibaba's Qwen 3 flagship model.", contextLength: 32768, provider: "Alibaba", isFree: false, pricing: { promptPer1k: 0.14, completionPer1k: 0.6 } },
  { id: "meta-llama/llama-3.3-70b-instruct", displayName: "Llama 3.3 70B", description: "Meta's Llama 3.3 70B instruction model.", contextLength: 131072, provider: "Meta", isFree: false, pricing: { promptPer1k: 0.06, completionPer1k: 0.06 } },
  { id: "deepseek/deepseek-r1", displayName: "DeepSeek R1", description: "DeepSeek's reasoning model.", contextLength: 163840, provider: "DeepSeek", isFree: false, pricing: { promptPer1k: 0.55, completionPer1k: 2.19 } },
];
