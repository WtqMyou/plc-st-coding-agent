"""自动化编译验证 harness：把"模型写 ST"变成"可度量的实验"。

回路长这样::

    题目 ──出题提示词──> 模型 ──回复──> 抠代码 ──> 编译+跑用例
                                                      │
                                          通过 ───────┴─────── 不通过
                                           │                     │
                                        记一条记录         把诊断回灌给模型
                                                                │
                                                      （最多 N 轮迭代）
"""

from .prompts import build_fix_prompt, build_system_prompt, build_task_prompt
from .runner import Attempt, RunRecord, Solver, solve_problem, solve_suite

__all__ = [
    "build_system_prompt",
    "build_task_prompt",
    "build_fix_prompt",
    "Attempt",
    "RunRecord",
    "Solver",
    "solve_problem",
    "solve_suite",
]
