"""离线通道：不做任何网络调用，按脚本返回 ST 代码。

存在的理由有两个，都不是"占位"：

1. **让整条 harness 在没有 API key 的机器上也能跑通**。队友克隆仓库、CI 跑冒烟
   测试、答辩现场断网演示，都不应该卡在"没有 key"上。
2. **做对照实验的"地板线"**。MockProvider 按固定策略生成代码，它的通过率
   就是"不靠模型智力能拿到多少分"的基线；模型比它高多少，才是模型的真实贡献。

策略由 ``script`` 决定：
* ``"echo_reference"``：直接吐出参考解——用来验证 harness 的"一次通过"路径；
* ``"blank"``：吐一个空壳 FB——用来验证编译失败路径与诊断信息是否可读；
* ``"sequence"``：按顺序吐 script 里的多个回复——用来**离线复现"改错重试"
  的完整多轮流程**（第一轮故意错，第二轮才对），这是最难靠人工点验的部分。
"""

from __future__ import annotations

from typing import Any

from .base import ChatMessage, Provider, ProviderResponse


class MockProvider(Provider):
    name = "mock"

    def __init__(
        self,
        model: str = "mock",
        script: str | list[str] = "echo_reference",
        reference: str | None = None,
        **kwargs: Any,
    ) -> None:
        super().__init__(model=model, **kwargs)
        self.script = script
        self.reference = reference or ""
        self._turn = 0

    def generate(self, messages: list[ChatMessage] | list[dict[str, str]]) -> ProviderResponse:
        idx = self._turn
        self._turn += 1
        text = self._reply(idx)
        return ProviderResponse(
            text=text,
            model="mock",
            usage={"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
            latency_s=0.0,
        )

    def _reply(self, idx: int) -> str:
        if isinstance(self.script, list):
            # 用完之后保持最后一条，避免 5 次重试时越界
            return self.script[min(idx, len(self.script) - 1)]
        if self.script == "echo_reference":
            return f"```st\n{self.reference}\n```"
        if self.script == "blank":
            return "```st\nFUNCTION_BLOCK FB\nEND_FUNCTION_BLOCK\n```"
        return f"```st\n{self.script}\n```"
