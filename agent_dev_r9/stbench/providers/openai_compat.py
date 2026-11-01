"""OpenAI Chat Completions 兼容通道。

一个类覆盖：OpenAI、DeepSeek、通义千问（dashscope compatible-mode）、
硅基流动、ollama、vLLM —— 它们都把 ``POST {base}/chat/completions`` 做成了同一套
请求/响应格式，差别只在 base_url 和 key。这也是为什么选它做主力通道：
换模型只换一行配置，实验代码一行不用动。
"""

from __future__ import annotations

from typing import Any

from .base import ChatMessage, Provider


class OpenAICompatProvider(Provider):
    name = "openai-compat"

    def __init__(self, model: str, base_url: str, api_key: str = "", **kwargs: Any) -> None:
        super().__init__(model=model, **kwargs)
        self.base_url = base_url
        self.api_key = api_key

    def _url(self) -> str:
        return f"{self.base_url}/chat/completions"

    def _headers(self) -> dict[str, str]:
        h = {"Content-Type": "application/json"}
        if self.api_key:
            h["Authorization"] = f"Bearer {self.api_key}"
        return h

    def _payload(self, messages: list[ChatMessage]) -> dict[str, Any]:
        p: dict[str, Any] = {
            "model": self.model,
            "messages": [m.to_dict() for m in messages],
            "max_tokens": self.max_tokens,
            "stream": False,
        }
        if self.temperature is not None:p["temperature"]=self.temperature
        # ollama / 部分推理模型不认 top_p 之外的花样，这里只透传显式给过的
        for k in ("top_p", "seed", "stop", "presence_penalty", "frequency_penalty"):
            if k in self.extra and self.extra[k] is not None:
                p[k] = self.extra[k]
        return p

    def _extract(self, data: dict[str, Any]) -> tuple[str, dict[str, int]]:
        choices = data.get("choices") or []
        if not choices:
            # 有些通道会在 200 里塞错误：{"error": {...}}
            err = data.get("error")
            raise ValueError(f"没有 choices：{err or str(data)[:300]}")
        msg = choices[0].get("message") or {}
        # 推理型模型（如 deepseek-reasoner）把正文放 content，思考过程放
        # reasoning_content；只取 content，否则提示词模板会把思考链误当代码。
        text = msg.get("content") or ""
        u = data.get("usage") or {}
        usage = {
            "prompt_tokens": int(u.get("prompt_tokens", 0) or 0),
            "completion_tokens": int(u.get("completion_tokens", 0) or 0),
            "total_tokens": int(u.get("total_tokens", 0) or 0),
        }
        return text, usage
