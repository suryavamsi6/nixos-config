import { type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getBuiltinModels, getBuiltinProviders } from "@earendil-works/pi-ai/providers/all";

const baseUrl = "http://bifrost.home.arpa/v1";

// Bifrost's /models endpoint carries no capability metadata (only id, created,
// owned_by and sometimes a display name/pricing), and /models/{id} answers
// "model_retrieve is not supported". So pi gets every model as text-only and
// non-reasoning, which hides the thinking-level selector and image attachments.
//
// Capabilities below reflect probes against the current Bifrost routes. The
// gateway does not advertise them, so new routes need to be checked separately.
// In particular, a successful request does not prove that thinking is emitted.
const VISION_MODELS = new Set([
  "CLIProxyAPI/codex-auto-review",
  "CLIProxyAPI/gpt-5.6-luna",
  "CLIProxyAPI/gpt-5.6-sol",
  "CLIProxyAPI/gpt-5.6-terra",
  "CLIProxyAPI/gpt-6-astra",
  "CLIProxyAPI/gpt-6-luna",
  "CLIProxyAPI/gpt-6-sol",
  "CLIProxyAPI/gpt-6.1-sol",
  "CLIProxyAPI/gpt-6.1-terra",
  "ZAI/glm-5.3-flash",
  "opencode-go/claude-haiku-5-5",
  "opencode-go/deepseek-v4.1-flash",
  "opencode-go/gemini-4-argon",
  "opencode-go/glm-5.3-flash",
  "opencode-go/gpt-5.6-luna",
  "opencode-go/grok-4.7",
  "opencode-go/kimi-k2.7-code",
  "opencode-go/kimi-k3",
  "opencode-go/kimi-k3.1-pro",
  "opencode-go/mimo-v2.6-flash",
  "opencode-go/mimo-v2.6-pro",
  "opencode-go/minimax-m3",
  "opencode-go/minimax-m3.1-flash",
  "opencode-go/muse-spark-1.2-contributor",
  "opencode-go/muse-spark-1.3-contributor",
  "opencode-go/qwen3.7-plus",
  "opencode-go/qwen3.8-flash",
  "opencode-go/qwen3.8-max",
  "opencode-go/step-5-preview",
]);

// Routes that reject reasoning_effort: xhigh/max, or return no reasoning at all.
const NO_HIGH_LEVELS = new Set(["opencode-go/mimo-v2.6-flash", "opencode-go/mimo-v2.6-pro"]);

// Routes that reject the OpenAI `developer` role and need `system`.
const NO_DEVELOPER_ROLE = new Set([
  "ZAI/glm-5.3-flash",
  "ZAI/glm-5.3-flashx",
  "opencode-go/kimi-k2.7-code",
  "opencode-go/kimi-k3.1-pro",
  "opencode-go/qwen3.7-plus",
  "opencode-go/qwen3.8-flash",
  "opencode-go/qwen3.8-max",
]);

// No reasoning was observed on these routes in the probes.
const NON_REASONING_PREFIX = "CLIProxyAPI/";

// Image-generation routes: pi only speaks image generation through
// "openrouter-images", so these cannot be chat models. Drop them from the list.
const IMAGE_GEN_PATTERN = /\/gpt-image-/;

type Twin = { maxTokens?: number; contextWindow?: number };

// Bifrost reports no limits, so borrow pi's own catalog entry for the same
// upstream model id (a route id such as "opencode-go/qwen3.8-max" matches the
// catalog id "qwen3.8-max"). Missing entries keep conservative defaults.
function loadLimits(): Map<string, Twin> {
  const limits = new Map<string, Twin>();
  for (const provider of getBuiltinProviders()) {
    for (const model of getBuiltinModels(provider)) {
      const key = model.id.toLowerCase();
      const current = limits.get(key);
      if (!current || ((current.maxTokens ?? 0) < (model.maxTokens ?? 0))) {
        limits.set(key, { maxTokens: model.maxTokens, contextWindow: model.contextWindow });
      }
    }
  }
  return limits;
}

function shortId(id: string): string {
  const slash = id.indexOf("/");
  return slash === -1 ? id : id.slice(slash + 1);
}

export default function (pi: ExtensionAPI) {
  // Bifrost routes the opencode-go/opencode-free models to OpenCode's console
  // API, which rejects requests without x-opencode-session. pi only adds that
  // header itself when the request target is opencode.ai, and here it is
  // bifrost.home.arpa, so supply the conversation id for bifrost requests.
  //
  // Bifrost does not forward arbitrary client headers upstream: only
  // x-bf-eh-* values are passed through, with the prefix stripped. So the
  // header is sent as x-bf-eh-x-opencode-session, which upstream receives as
  // x-opencode-session. x-bf-vk identifies bifrost requests; models.json
  // sends it on every one.
  pi.on("before_provider_headers", (event, ctx) => {
    const isBifrost = Object.keys(event.headers).some((name) => name.toLowerCase() === "x-bf-vk");
    if (!isBifrost) return;

    const sessionId = ctx.sessionManager.getSessionId();
    if (sessionId) {
      event.headers["x-bf-eh-x-opencode-session"] = sessionId;
    }
  });

  pi.registerProvider("bifrost", {
    name: "Bifrost",
    baseUrl,
    api: "openai-completions",
    refreshModels: async ({ signal }) => {
      const apiKey = process.env.BIFROST_API_KEY;
      if (!apiKey) throw new Error("BIFROST_API_KEY is not set");

      const response = await fetch(`${baseUrl}/models`, {
        headers: { Authorization: `Bearer ${apiKey}`, "x-bf-vk": apiKey },
        signal,
      });
      if (!response.ok) {
        throw new Error(`Bifrost /models returned HTTP ${response.status}`);
      }

      const limits = loadLimits();
      const body = (await response.json()) as {
        data?: Array<{ id?: string; name?: string; context_length?: number }>;
      };

      return (body.data ?? [])
        .map((model) => ({ ...model, id: model.id ?? "" }))
        .filter((model) => model.id.length > 0 && !IMAGE_GEN_PATTERN.test(model.id))
        .map((model) => {
          const id = model.id;
          const twin = limits.get(shortId(id).toLowerCase());
          const reasoning = !id.startsWith(NON_REASONING_PREFIX);
          const noHigh = NO_HIGH_LEVELS.has(id);

          return {
            id,
            name: model.name ?? id,
            api: "openai-completions" as const,
            type: "chat" as const,
            input: (VISION_MODELS.has(id) ? ["text", "image"] : ["text"]) as ("text" | "image")[],
            reasoning,
            // Null levels are hidden by pi; off omits reasoning_effort.
            ...(reasoning
              ? {
                  thinkingLevelMap: {
                    off: null,
                    minimal: null,
                    low: "low",
                    medium: "medium",
                    high: "high",
                    xhigh: noHigh ? null : "xhigh",
                    max: noHigh ? null : "max",
                  },
                }
              : {}),
            compat: {
              // Bifrost speaks plain OpenAI reasoning_effort to every upstream;
              // pi must not apply a native provider's thinking wire format.
              thinkingFormat: "openai" as const,
              supportsReasoningEffort: true,
              supportsDeveloperRole: !NO_DEVELOPER_ROLE.has(id),
            },
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
            contextWindow: model.context_length ?? twin?.contextWindow ?? 128000,
            maxTokens: twin?.maxTokens ?? 8192,
          };
        });
    },
  });
}
