"""Anthropic Messages 通道。

和 OpenAI 协议的差异有三处，抄错任何一处都会 400：
1. ``system`` 提示词是**顶层字段**，不能放进 messages 数组；
2. ``max_tokens`` **必填**；
3. 响应 ``content`` 是块列表（可能含 thinking 块），要把 ``type == "text"`` 的块拼起来。
"""

from __future__ import annotations

from typing import Any

from .base import ChatMessage, Provider


class AnthropicProvider(Provider):
    name = "anthropic"

    ANTHROPIC_VERSION = "2023-06-01"

    def __init__(self, model: str, base_url: str = "https://api.anthropic.com", api_key: str = "", **kwargs: Any) -> None:
        super().__init__(model=model, **kwargs)
        self.base_url = base_url
        self.api_key = api_key

    def _url(self) -> str:
        return f"{self.base_url}/v1/messages"

    def _headers(self) -> dict[str, str]:
        return {
            "Content-Type": "application/json",
            "x-api-key": self.api_key,
            "anthropic-version": self.ANTHROPIC_VERSION,
        }

    def _payload(self, messages: list[ChatMessage]) -> dict[str, Any]:
        system = "\n\n".join(m.content for m in messages if m.role == "system")
        convo = [m.to_dict() for m in messages if m.role != "system"]
        p: dict[str, Any] = {
            "model": self.model,
            "max_tokens": self.max_tokens,
            "messages": convo,
        }
        if system:
            p["system"] = system
        if self.temperature is not None:
            p["temperature"] = self.temperature
        for k in ("top_p", "top_k", "stop_sequences"):
            if k in self.extra and self.extra[k] is not None:
                p[k] = self.extra[k]
        return p

    def _extract(self, data: dict[str, Any]) -> tuple[str, dict[str, int]]:
        blocks = data.get("content") or []
        text = "".join(b.get("text", "") for b in blocks if b.get("type") == "text")
        u = data.get("usage") or {}
        usage = {
            "prompt_tokens": int(u.get("input_tokens", 0) or 0),
            "completion_tokens": int(u.get("output_tokens", 0) or 0),
            "total_tokens": int(u.get("input_tokens", 0) or 0) + int(u.get("output_tokens", 0) or 0),
        }
        return text, usage
