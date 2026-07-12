import os
import logging
from abc import ABC, abstractmethod

logger = logging.getLogger(__name__)

class LLMProvider(ABC):
    name: str

    @abstractmethod
    def generate(self, system_prompt: str, user_message: str,
                 temperature: float = 0.0) -> str:
        ...


class GroqProvider(LLMProvider):
    name = "groq"

    def generate(self, system_prompt: str, user_message: str,
                 temperature: float = 0.0) -> str:
        from groq_client import call_groq
        return call_groq(
            system_prompt=system_prompt,
            user_message=user_message,
            temperature=temperature,
        )


class ClaudeProvider(LLMProvider):
    name = "claude"

    def generate(self, system_prompt: str, user_message: str,
                 temperature: float = 0.0) -> str:
        raise NotImplementedError(
            "ClaudeProvider is not wired up - this project uses Groq in production. "
            "See docs/llm_comparison.md for the manual output comparison."
        )


PROVIDERS = {
    "groq": GroqProvider,
    "claude": ClaudeProvider,
}


def get_provider(name: str | None = None) -> LLMProvider:
    name = (name or os.getenv("AI_PROVIDER", "groq")).lower()

    if name not in PROVIDERS:
        raise ValueError(
            f"Unknown AI provider '{name}'. Available: {sorted(PROVIDERS)}"
        )

    logger.info("Using LLM provider: %s", name)
    return PROVIDERS[name]()