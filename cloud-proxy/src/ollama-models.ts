import type { Env } from "./types";

// Cache key and TTL for Ollama models in KV
const CACHE_KEY = "ollama:models:v1";
const CACHE_TTL = 3600; // 1 hour

export interface OllamaRegistryModel {
  name: string;
  displayName: string;
  description: string;
  parameterSize: string | null;
  availableSizes: string[];
  tags: string[];
  pullCount: string;
}

interface CachedModels {
  models: OllamaRegistryModel[];
  fetchedAt: string;
}

export async function handleOllamaModels(
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  // 1. Try KV cache first
  const cached = await env.KV.get(CACHE_KEY, "json") as CachedModels | null;
  if (cached && cached.models.length > 0) {
    return Response.json({
      models: cached.models,
      source: "cache",
      fetchedAt: cached.fetchedAt,
    }, {
      headers: {
        "Cache-Control": "public, max-age=600",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }

  // 2. Fetch from ollama.com/library
  let models: OllamaRegistryModel[];
  try {
    models = await scrapeOllamaLibrary();
  } catch (err) {
    // If scrape fails and we have stale cache, return it
    if (cached) {
      return Response.json({
        models: cached.models,
        source: "stale-cache",
        fetchedAt: cached.fetchedAt,
      });
    }
    // No cache at all — return fallback
    return Response.json({
      models: FALLBACK_MODELS,
      source: "fallback",
      fetchedAt: new Date().toISOString(),
    });
  }

  if (models.length === 0) {
    return Response.json({
      models: FALLBACK_MODELS,
      source: "fallback",
      fetchedAt: new Date().toISOString(),
    });
  }

  // 3. Store in KV (non-blocking)
  const cacheData: CachedModels = {
    models,
    fetchedAt: new Date().toISOString(),
  };
  ctx.waitUntil(
    env.KV.put(CACHE_KEY, JSON.stringify(cacheData), {
      expirationTtl: CACHE_TTL,
    })
  );

  return Response.json({
    models,
    source: "live",
    fetchedAt: cacheData.fetchedAt,
  }, {
    headers: {
      "Cache-Control": "public, max-age=600",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

// ─── Scraper ──────────────────────────────────────────────────────

async function scrapeOllamaLibrary(): Promise<OllamaRegistryModel[]> {
  const response = await fetch("https://ollama.com/library", {
    headers: {
      "User-Agent": "PromptCraft-CloudProxy/1.0",
    },
    cf: { cacheTtl: 300 }, // Cloudflare edge cache for 5 min
  });

  if (!response.ok) {
    throw new Error(`ollama.com returned ${response.status}`);
  }

  const html = await response.text();
  return parseLibraryHTML(html);
}

function parseLibraryHTML(html: string): OllamaRegistryModel[] {
  const models: OllamaRegistryModel[] = [];

  // Match model card anchors: <a href="/library/MODEL_NAME" class="group
  const cardRegex = /<a href="\/library\/([^"]+)" class="group/g;
  const cardStarts: { name: string; index: number }[] = [];

  let match: RegExpExecArray | null;
  while ((match = cardRegex.exec(html)) !== null) {
    cardStarts.push({ name: match[1], index: match.index });
  }

  for (let i = 0; i < cardStarts.length; i++) {
    const { name, index: start } = cardStarts[i];
    const end = i + 1 < cardStarts.length ? cardStarts[i + 1].index : start + 3000;
    const cardHTML = html.slice(start, Math.min(end, start + 3000));

    // Skip embedding/non-generation models
    if (/embed|nomic|mxbai|bge/i.test(name)) continue;

    // Extract description
    const descMatch = cardHTML.match(/text-neutral-800 text-md">([\s\S]*?)<\/p>/);
    let description = descMatch?.[1]?.trim() ?? "";
    // Strip leading emoji
    description = description.replace(/^[^\x00-\x7F\s]+\s*/, "");
    description = description.slice(0, 120);

    // Extract capabilities (tags)
    const tags: string[] = [];
    const capRegex = /x-test-capability[^>]*>([^<]+)</g;
    let capMatch: RegExpExecArray | null;
    while ((capMatch = capRegex.exec(cardHTML)) !== null) {
      const tag = capMatch[1].trim();
      if (tag) tags.push(tag);
    }

    // Extract sizes
    const sizes: string[] = [];
    const sizeRegex = /x-test-size[^>]*>([^<]+)</g;
    let sizeMatch: RegExpExecArray | null;
    while ((sizeMatch = sizeRegex.exec(cardHTML)) !== null) {
      const size = sizeMatch[1].trim();
      if (size) sizes.push(size);
    }

    // Extract pull count
    const pullMatch = cardHTML.match(/x-test-pull-count>([^<]+)</);
    const pullCount = pullMatch?.[1]?.trim() ?? "";

    // Pick preferred size (7-14B range)
    const preferredSize = pickPreferredSize(sizes);

    models.push({
      name,
      displayName: formatDisplayName(name),
      description,
      parameterSize: preferredSize,
      availableSizes: sizes,
      tags,
      pullCount,
    });
  }

  return models;
}

function pickPreferredSize(sizes: string[]): string | null {
  if (sizes.length === 0) return null;
  const preferred = ["8b", "7b", "14b", "12b", "4b", "3b", "9b", "1b"];
  for (const p of preferred) {
    if (sizes.some((s) => s.toLowerCase() === p)) return p.toUpperCase();
  }
  return sizes[0].toUpperCase();
}

function formatDisplayName(name: string): string {
  return name
    .split(/[-.]/)
    .map((part) => {
      if (/^\d+(\.\d+)?$/.test(part)) return part;
      return part.charAt(0).toUpperCase() + part.slice(1);
    })
    .join(" ")
    .replace(/Llama/g, "Llama")
    .replace(/Deepseek/g, "DeepSeek")
    .replace(/Openai/g, "OpenAI");
}

// ─── Fallback ─────────────────────────────────────────────────────

const FALLBACK_MODELS: OllamaRegistryModel[] = [
  { name: "qwen3", displayName: "Qwen 3", description: "Latest generation with dense and mixture-of-experts configurations.", parameterSize: "8B", availableSizes: ["0.6b","1.7b","4b","8b","14b","30b","32b","235b"], tags: ["thinking","tools"], pullCount: "19.2M" },
  { name: "llama3.1", displayName: "Llama 3.1", description: "State-of-the-art model from Meta available in 8B, 70B and 405B parameter sizes.", parameterSize: "8B", availableSizes: ["8b","70b","405b"], tags: ["tools"], pullCount: "110.2M" },
  { name: "deepseek-r1", displayName: "DeepSeek R1", description: "Open reasoning model with performance approaching leading proprietary systems.", parameterSize: "8B", availableSizes: ["1.5b","7b","8b","14b","32b","70b","671b"], tags: ["thinking"], pullCount: "78.1M" },
  { name: "gemma3", displayName: "Gemma 3", description: "Capable single-GPU models from Google.", parameterSize: "12B", availableSizes: ["1b","4b","12b","27b"], tags: ["vision","tools"], pullCount: "31.8M" },
  { name: "phi4", displayName: "Phi 4", description: "State-of-the-art open model from Microsoft.", parameterSize: "14B", availableSizes: ["14b"], tags: ["tools"], pullCount: "7.2M" },
  { name: "mistral", displayName: "Mistral", description: "The 7B model released by Mistral AI, updated to version 0.3.", parameterSize: "7B", availableSizes: ["7b"], tags: [], pullCount: "25.2M" },
  { name: "llama3.2", displayName: "Llama 3.2", description: "Meta's lightweight models optimized for compact deployment.", parameterSize: "3B", availableSizes: ["1b","3b"], tags: [], pullCount: "57.1M" },
  { name: "qwen2.5", displayName: "Qwen 2.5", description: "Models pretrained on extensive datasets supporting 128K tokens.", parameterSize: "7B", availableSizes: ["0.5b","1.5b","3b","7b","14b","32b","72b"], tags: ["tools"], pullCount: "21.3M" },
  { name: "gemma2", displayName: "Gemma 2", description: "High-performing efficient models from Google.", parameterSize: "9B", availableSizes: ["2b","9b","27b"], tags: [], pullCount: "15.8M" },
  { name: "llama3.3", displayName: "Llama 3.3", description: "Offers similar performance to Llama 3.1 405B.", parameterSize: "70B", availableSizes: ["70b"], tags: ["tools"], pullCount: "3.3M" },
];
