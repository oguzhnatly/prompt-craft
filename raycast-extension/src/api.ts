import { getPreferenceValues } from "@raycast/api";

interface Preferences {
  apiToken: string;
  port?: string;
}

function getBaseURL(): string {
  const { port } = getPreferenceValues<Preferences>();
  return `http://127.0.0.1:${port || "9847"}`;
}

function getToken(): string {
  const { apiToken } = getPreferenceValues<Preferences>();
  return apiToken;
}

export async function checkHealth(): Promise<{ status: string; version: string }> {
  const res = await fetch(`${getBaseURL()}/health`, {
    method: "GET",
  });

  if (!res.ok) {
    throw new Error(`Health check failed (${res.status})`);
  }

  return (await res.json()) as { status: string; version: string };
}

export interface OptimizeRequest {
  text: string;
  styleId?: string;
  verbosity?: "concise" | "balanced" | "detailed";
}

export interface OptimizeResponse {
  output: string;
  tier: string;
  tokens: number;
  durationMs: number;
  style: string;
  provider: string;
  model: string;
}

export async function optimize(request: OptimizeRequest): Promise<OptimizeResponse> {
  const res = await fetch(`${getBaseURL()}/optimize`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${getToken()}`,
    },
    body: JSON.stringify(request),
  });

  const body = (await res.json()) as OptimizeResponse & { error?: string };

  if (!res.ok) {
    throw new Error(body.error || `Optimization failed (${res.status})`);
  }

  return body;
}

export interface StyleInfo {
  id: string;
  name: string;
  description: string;
  category: string;
  icon: string;
}

export async function getStyles(): Promise<StyleInfo[]> {
  const res = await fetch(`${getBaseURL()}/styles`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${getToken()}`,
    },
  });

  const body = (await res.json()) as { styles: StyleInfo[]; error?: string };

  if (!res.ok) {
    throw new Error(body.error || `Failed to fetch styles (${res.status})`);
  }

  return body.styles;
}
