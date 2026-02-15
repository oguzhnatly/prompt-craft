// Normalizes provider SSE streams to the Anthropic-style format
// that the PromptCraft macOS app expects:
//
//   data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}
//   data: [DONE]

export function normalizeStream(
  providerName: string,
  upstreamBody: ReadableStream<Uint8Array>
): ReadableStream<Uint8Array> {
  if (providerName === "claude") {
    // Claude's native format already matches what the app expects.
    // Pass through directly — zero processing overhead.
    return upstreamBody;
  }

  // OpenAI and DeepSeek use the same SSE format:
  //   data: {"choices":[{"delta":{"content":"text"}}]}
  //   data: [DONE]
  // We convert to Anthropic format.
  return convertOpenAIStream(upstreamBody);
}

function convertOpenAIStream(
  upstream: ReadableStream<Uint8Array>
): ReadableStream<Uint8Array> {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";

  return new ReadableStream({
    async start(controller) {
      const reader = upstream.getReader();

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) {
            // Flush any remaining buffer
            if (buffer.trim()) {
              processLines(buffer, controller, encoder);
            }
            // Send final [DONE]
            controller.enqueue(encoder.encode("data: [DONE]\n\n"));
            controller.close();
            return;
          }

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          // Keep the last (potentially incomplete) line in the buffer
          buffer = lines.pop() ?? "";

          for (const line of lines) {
            processLine(line.trim(), controller, encoder);
          }
        }
      } catch (err) {
        controller.error(err);
      }
    },
  });
}

function processLines(
  text: string,
  controller: ReadableStreamDefaultController<Uint8Array>,
  encoder: TextEncoder
): void {
  for (const line of text.split("\n")) {
    processLine(line.trim(), controller, encoder);
  }
}

function processLine(
  line: string,
  controller: ReadableStreamDefaultController<Uint8Array>,
  encoder: TextEncoder
): void {
  if (!line.startsWith("data: ")) return;

  const payload = line.slice(6).trim();

  if (payload === "[DONE]") {
    controller.enqueue(encoder.encode("data: [DONE]\n\n"));
    return;
  }

  try {
    const parsed = JSON.parse(payload) as {
      choices?: Array<{
        delta?: { content?: string };
        finish_reason?: string | null;
      }>;
    };

    const text = parsed.choices?.[0]?.delta?.content;
    if (text !== undefined && text !== null && text !== "") {
      const event = {
        type: "content_block_delta",
        delta: { type: "text_delta", text },
      };
      controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
    }
  } catch {
    // Skip malformed lines — do not log content (zero-storage policy)
  }
}
