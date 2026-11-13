"""模型通道（provider）抽象层。

大作业要求"两个基座模型"做对照实验，所以**模型调用必须是一个可替换的薄接口**：
harness 只认识 ``Provider.generate(messages) -> str``，不关心背后是 DeepSeek、
Claude 还是本地 llama。这样换模型只改一个配置项，不动实验代码——
否则"两个模型"会变成两份分叉的实验脚本，对照组就不可比了。

设计取舍
--------
* **不引入任何第三方 SDK**。两个通道都只是 HTTPS POST，用标准库 ``urllib``
  就能发。少一个依赖就少一处"在我机器上能跑"的风险，队友克隆下来直接能用。
* **OpenAI 兼容协议优先**。DeepSeek / Qwen / vLLM / ollama 都实现了
  ``/v1/chat/completions``，所以一个 ``OpenAICompatProvider`` 就覆盖了绝大多数
  国产模型和本地部署，只在 base_url 上区分。
* **Anthropic 单独一个类**，因为它的请求体（``system`` 独立字段、``max_tokens``
  必填）和响应体（``content`` 是块列表）都不一样。
* **重试放在这一层**。模型 API 的 429/5xx 是常态，如果不在 provider 里重试，
  一次网络抖动就会污染实验日志，让"该模型失败"的记录变成"这次网络不好"。

离线可测
--------
``MockProvider`` 让整条 harness 在没有 key 的机器上也能跑通——
这既是 CI 的保障，也是答辩时"演示不依赖网络"的兜底。
"""

from .base import (
    ChatMessage,
    Provider,
    ProviderError,
    ProviderResponse,
    get_provider,
)
from .mock import MockProvider
from .openai_compat import OpenAICompatProvider
from .anthropic import AnthropicProvider

__all__ = [
    "ChatMessage",
    "Provider",
    "ProviderError",
    "ProviderResponse",
    "get_provider",
    "MockProvider",
    "OpenAICompatProvider",
    "AnthropicProvider",
]
