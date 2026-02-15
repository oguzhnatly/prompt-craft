import type { Env, OptimizeRequest, ProviderConfig, Message } from "./types";

// Model aliases map cloud-tier model names to real provider models
const MODEL_ALIASES: Record<string, { provider: string; model: string }> = {
  "pc-standard": { provider: "deepseek", model: "deepseek-chat" },
  "pc-fast": { provider: "deepseek", model: "deepseek-chat" },
};

function formatClaudeBody(req: OptimizeRequest): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model: req.model,
    max_tokens: req.max_tokens ?? 4096,
    temperature: req.temperature ?? 0.7,
    stream: true,
    messages: req.messages.filter((m) => m.role !== "system"),
  };

  // Claude uses a top-level "system" field
  const systemMsg = req.messages.find((m) => m.role === "system");
  if (systemMsg) {
    body.system = systemMsg.content;
  }
  if (req.system) {
    body.system = req.system;
  }

  return body;
}

function formatOpenAIBody(req: OptimizeRequest): Record<string, unknown> {
  const messages: Message[] = [];

  // OpenAI/DeepSeek use system as a message role
  if (req.system) {
    messages.push({ role: "system", content: req.system });
  }
  messages.push(...req.messages);

  return {
    model: req.model,
    max_tokens: req.max_tokens ?? 4096,
    temperature: req.temperature ?? 0.7,
    stream: true,
    messages,
  };
}

const PROVIDERS: Record<string, ProviderConfig> = {
  claude: {
    url: "https://api.anthropic.com/v1/messages",
    authHeader: "x-api-key",
    authPrefix: "",
    apiKeyEnvName: "CLAUDE_API_KEY",
    formatBody: formatClaudeBody,
  },
  deepseek: {
    url: "https://api.deepseek.com/v1/chat/completions",
    authHeader: "Authorization",
    authPrefix: "Bearer ",
    apiKeyEnvName: "DEEPSEEK_API_KEY",
    formatBody: formatOpenAIBody,
  },
  openai: {
    url: "https://api.openai.com/v1/chat/completions",
    authHeader: "Authorization",
    authPrefix: "Bearer ",
    apiKeyEnvName: "OPENAI_API_KEY",
    formatBody: formatOpenAIBody,
  },
};

export interface ResolvedProvider {
  config: ProviderConfig;
  providerName: string;
  resolvedModel: string;
  apiKey: string;
}

export function resolveProvider(
  req: OptimizeRequest,
  env: Env
): ResolvedProvider | null {
  let providerName = req.provider ?? "";
  let model = req.model;

  // Check if the model is a cloud alias (pc-standard, pc-fast)
  const alias = MODEL_ALIASES[model];
  if (alias) {
    providerName = alias.provider;
    model = alias.model;
  }

  // Default to deepseek if no provider resolved
  if (!providerName) {
    providerName = "deepseek";
  }

  const config = PROVIDERS[providerName];
  if (!config) {
    return null;
  }

  const apiKey = env[config.apiKeyEnvName];
  if (!apiKey) {
    return null;
  }

  return { config, providerName, resolvedModel: model, apiKey };
}

export async function forwardToProvider(
  req: OptimizeRequest,
  resolved: ResolvedProvider
): Promise<Response> {
  const { config, resolvedModel, apiKey } = resolved;

  // Override model to the resolved one
  const requestWithModel = { ...req, model: resolvedModel };
  const body = config.formatBody(requestWithModel);

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    [config.authHeader]: `${config.authPrefix}${apiKey}`,
  };

  // Claude requires anthropic-version header
  if (resolved.providerName === "claude") {
    headers["anthropic-version"] = "2023-06-01";
  }

  const response = await fetch(config.url, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });

  return response;
}
