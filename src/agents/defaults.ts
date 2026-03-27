// Defaults for agent metadata when upstream does not supply them.
// Arny distribution: prefer local Ollama so embedded runs do not require cloud API keys.
export const DEFAULT_PROVIDER = "ollama";
export const DEFAULT_MODEL = "qwen3.5:latest";
// Conservative fallback used when model metadata is unavailable.
export const DEFAULT_CONTEXT_TOKENS = 200_000;
