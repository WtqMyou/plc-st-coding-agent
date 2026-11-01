"""Provider 接口与公共工具：重试、token 统计、从回复里抠代码块。"""

from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any


class ProviderError(RuntimeError):
    """模型调用失败（网络、鉴权、限流重试耗尽、返回体不合规）。"""


@dataclass
class ChatMessage:
    role: str  # "system" | "user" | "assistant"
    content: str

    def to_dict(self) -> dict[str, str]:
        return {"role": self.role, "content": self.content}


@dataclass
class ProviderResponse:
    """一次模型调用的结果。

    ``text`` 是原始回复全文，``usage`` 记 token 用量（如果上游给了）——
    论文里报"每道题平均消耗多少 token"要靠它，而不能靠字符数估算。
    """

    text: str
    model: str = ""
    usage: dict[str, int] = field(default_factory=dict)
    raw: dict[str, Any] | None = None
    latency_s: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "text": self.text,
            "model": self.model,
            "usage": self.usage,
            "latency_s": round(self.latency_s, 3),
        }


class Provider:
    """所有模型通道的基类。

    子类只需实现 ``_post(url, headers, payload) -> dict`` 和 ``_extract(data)``。
    """

    name: str = "base"

    def __init__(
        self,
        model: str,
        temperature: float = 0.0,
        max_tokens: int = 4096,
        timeout: float = 180.0,
        max_retries: int = 4,
        **kwargs: Any,
    ) -> None:
        self.model = model
        # 默认温度为 0：这是**代码生成实验**，不是创作。贪心解码让
        # "同一模型跑两次结果不同"的干扰项消失，对照实验才可复现。
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.timeout = timeout
        self.max_retries = max_retries
        self.extra = kwargs

    # ---- 子类实现 ----
    def _payload(self, messages: list[ChatMessage]) -> dict[str, Any]:
        raise NotImplementedError

    def _url(self) -> str:
        raise NotImplementedError

    def _headers(self) -> dict[str, str]:
        raise NotImplementedError

    def _extract(self, data: dict[str, Any]) -> tuple[str, dict[str, int]]:
        raise NotImplementedError

    # ---- 公共流程 ----
    def generate(self, messages: list[ChatMessage] | list[dict[str, str]]) -> ProviderResponse:
        if not self.extra.get("live_authorized", False):
            raise ProviderError("真实模型调用已锁定：必须先显式配置至少两个模型及调用预算")
        msgs = [
            m if isinstance(m, ChatMessage) else ChatMessage(m["role"], m["content"])
            for m in messages
        ]
        payload = self._payload(msgs)
        last_err: Exception | None = None
        for attempt in range(self.max_retries):
            t0 = time.time()
            try:
                data = _post_json(self._url(), self._headers(), payload, self.timeout)
                text, usage = self._extract(data)
                return ProviderResponse(
                    text=text,
                    model=data.get("model", self.model),
                    usage=usage,
                    raw=data,
                    latency_s=time.time() - t0,
                )
            except urllib.error.HTTPError as e:
                body = _safe_read(e)
                last_err = ProviderError(f"HTTP {e.code}: {body[:500]}")
                # 4xx 里只有 429 值得重试；其余（401/400）重试毫无意义，
                # 反而浪费时间并刷出一堆同样的报错日志。
                if e.code not in (408, 409, 425, 429) and e.code < 500:
                    raise last_err from e
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                last_err = ProviderError(f"网络错误: {e}")
            except (KeyError, TypeError, ValueError) as e:
                last_err = ProviderError(f"返回体解析失败: {e}")
            # 指数退避 + 抖动：多进程并发跑实验时避免同步重试形成尖峰
            if attempt < self.max_retries - 1:
                time.sleep(min(2 ** attempt, 20) * (0.5 + 0.5 * _jitter()))
        raise ProviderError(f"{self.name} 调用失败（重试 {self.max_retries} 次）：{last_err}")


def _jitter() -> float:
    # 用 os.urandom 而不是 random：避免和实验里的随机种子互相影响
    return int.from_bytes(os.urandom(2), "big") / 65535.0


def _safe_read(e: urllib.error.HTTPError) -> str:
    try:
        return e.read().decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 - 读错误体本身失败时不该再抛
        return ""


def _post_json(url: str, headers: dict[str, str], payload: dict[str, Any], timeout: float) -> dict[str, Any]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8", "replace")
    return json.loads(raw)


# ---------------------------------------------------------------- 代码抽取
_FENCE = re.compile(r"```[ \t]*([A-Za-z0-9_+-]*)[ \t]*\r?\n(.*?)```", re.S)


def extract_code(text: str, lang_hints: tuple[str, ...] = ("", "st", "iec", "structured-text", "pascal", "pou", "text", "plc")) -> str:
    """从模型回复里抠出 ST 代码块。

    为什么必须有这一步：模型几乎不会只回代码，它会写"好的，下面是实现……"
    再加一个 ``` 围栏。直接把全文丢给编译器，第一行就会报"无法解析的语句"，
    而这种失败**不是模型能力问题**，是搬运问题——会让实验数据系统性偏低。

    选择规则：优先带 ST 相关语言标记的块；否则取**最长**的块（模型有时先写
    一个片段示例再写完整实现，最长的那块通常是完整 FB）。
    """
    blocks = [(lang.lower().strip(), code) for lang, code in _FENCE.findall(text)]
    if not blocks:
        # 没有围栏：如果正文里出现了 FB 关键字，就当整篇是代码
        if re.search(r"\b(FUNCTION_BLOCK|FUNCTION|PROGRAM)\b", text, re.I):
            return text.strip()
        return text.strip()

    def score(item: tuple[str, str]) -> tuple[int, int]:
        lang, code = item
        return (1 if lang in lang_hints else 0, len(code))

    return max(blocks, key=score)[1].strip()


# ---------------------------------------------------------------- 工厂
def get_provider(spec: str | None = None, **overrides: Any) -> Provider:
    """按 ``"provider:model"`` 或 ``"model"`` 造一个通道。

    例子::

        get_provider("deepseek:deepseek-chat")
        get_provider("anthropic:claude-sonnet-4-5")      # 读 ANTHROPIC_API_KEY
        get_provider("openai:gpt-4o-mini")
        get_provider("mock")                             # 离线跑通全流程

    环境变量约定（都不进代码仓库）：``DEEPSEEK_API_KEY`` / ``OPENAI_API_KEY`` /
    ``ANTHROPIC_API_KEY``。base_url 可用 ``<NAME>_BASE_URL`` 覆盖。
    """
    from .anthropic import AnthropicProvider
    from .mock import MockProvider
    from .openai_compat import OpenAICompatProvider

    spec = spec or os.environ.get("STBENCH_PROVIDER") or "mock"
    if ":" in spec:
        kind, model = spec.split(":", 1)
    else:
        kind, model = spec, spec

    kind = kind.lower().strip()
    if kind in ("mock", "offline", "dummy"):
        return MockProvider(model="mock", **overrides)
    if kind in ("deepseek", "openai", "openai-compat", "qwen", "dashscope", "ollama", "vllm", "siliconflow"):
        presets = {
            "deepseek": ("https://api.deepseek.com/v1", "DEEPSEEK_API_KEY"),
            "qwen": ("https://dashscope.aliyuncs.com/compatible-mode/v1", "DASHSCOPE_API_KEY"),
            "dashscope": ("https://dashscope.aliyuncs.com/compatible-mode/v1", "DASHSCOPE_API_KEY"),
            "siliconflow": ("https://api.siliconflow.cn/v1", "SILICONFLOW_API_KEY"),
            "ollama": ("http://localhost:11434/v1", ""),
            "vllm": ("http://localhost:8000/v1", ""),
            "openai": ("https://api.openai.com/v1", "OPENAI_API_KEY"),
        }
        default_base, key_env = presets.get(kind, ("", "OPENAI_API_KEY"))
        base = os.environ.get(f"{kind.upper()}_BASE_URL") or os.environ.get("OPENAI_BASE_URL") or default_base
        key = os.environ.get(key_env, "") if key_env else ""
        if not key and key_env:
            raise ProviderError(
                f"缺少环境变量 {key_env}。请先 set {key_env}=... 再跑实验"
                f"（或设 STBENCH_PROVIDER=mock 离线跑通流程）"
            )
        return OpenAICompatProvider(model=model, base_url=base.rstrip("/"), api_key=key, **overrides)
    if kind in ("anthropic", "claude"):
        key = os.environ.get("ANTHROPIC_API_KEY", "")
        if not key:
            raise ProviderError("缺少环境变量 ANTHROPIC_API_KEY")
        base = os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com")
        return AnthropicProvider(model=model, base_url=base.rstrip("/"), api_key=key, **overrides)

    raise ProviderError(f"未知的 provider 类型 {kind!r}；可用：mock / deepseek / openai / qwen / anthropic / ollama / vllm")
