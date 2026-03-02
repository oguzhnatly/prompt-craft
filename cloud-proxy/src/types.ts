export interface Env {
  KV: KVNamespace;
  CLAUDE_API_KEY: string;
  DEEPSEEK_API_KEY: string;
  OPENAI_API_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  STRIPE_SECRET_KEY: string;
  RESEND_API_KEY: string;
  PROXY_VERSION: string;
}

export interface OptimizeRequest {
  license_key?: string;
  provider?: "claude" | "deepseek" | "openai";
  model: string;
  messages: Message[];
  system?: string;
  max_tokens?: number;
  temperature?: number;
  stream?: boolean;
}

export interface Message {
  role: "user" | "assistant" | "system";
  content: string;
}

export interface ProviderConfig {
  url: string;
  authHeader: string;
  authPrefix: string;
  apiKeyEnvName: keyof Pick<Env, "CLAUDE_API_KEY" | "DEEPSEEK_API_KEY" | "OPENAI_API_KEY">;
  formatBody: (req: OptimizeRequest) => Record<string, unknown>;
}

export interface ProxyError {
  error: string;
  message: string;
  retry_after?: number;
}

export interface AccessLog {
  license_hash: string;
  timestamp: string;
  provider: string;
  model: string;
  status: number;
  latency_ms: number;
}
