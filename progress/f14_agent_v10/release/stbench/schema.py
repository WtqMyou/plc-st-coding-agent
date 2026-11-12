"""数据集统一 schema。

整条流水线（解析 → 提示词 → 编译检查 → 仿真测试 → 指标汇总）都只认这里的
数据结构，因此只要把题目整理成 Problem，后面的环节与题目来源无关。

设计取舍
--------
* ``Problem`` 是**只读的事实**（题目本身），不掺任何运行结果；
* ``RunResult`` 是**一次运行的证据**，两者分开存盘，便于复现与审计；
* 所有文件用 UTF-8 + JSON，保证中文/英文题目、LTL 公式、ST 代码原样往返。
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any


class Difficulty(str, Enum):
    EASY = "easy"
    MEDIUM = "medium"
    HARD = "hard"


class Direction(str, Enum):
    INPUT = "input"
    OUTPUT = "output"
    INOUT = "inout"


@dataclass
class VarDef:
    """一个接口变量（或结构体字段）。

    ``direction=inout`` 对应题目里的 "Input/Output"（引用传递，PLC 侧只读或只写
    其中一部分字段），这是 CODESYS 里 ``VAR_IN_OUT`` 的语义。
    """

    name: str
    data_type: str
    description: str = ""
    direction: Direction = Direction.INPUT
    # 结构体的单行签名，例如 "ARRAY[1..5] OF ST_Pump"
    # 为 None 表示普通标量/数组
    # 字段说明表格（题目里用 **Data type ST_Pump** 段落给出）
    fields: list["VarDef"] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "data_type": self.data_type,
            "description": self.description,
            "direction": self.direction.value,
            "fields": [f.to_dict() for f in self.fields],
        }

    @staticmethod
    def from_dict(d: dict[str, Any]) -> "VarDef":
        return VarDef(
            name=d["name"],
            data_type=d["data_type"],
            description=d.get("description", ""),
            direction=Direction(d.get("direction", "input")),
            fields=[VarDef.from_dict(f) for f in d.get("fields", [])],
        )


@dataclass
class Problem:
    """一道 ST 代码生成题。

    ``pid`` 是全局唯一编号，命名规则 ``<来源>-<难度>-<序号>``，例如
    ``pub-easy-01``（公共题）、``self-hard-03``（自建题）。运行结果的文件名、
    日志目录全部用它，避免中英文标题带来的路径问题。
    """

    pid: str
    source: str  # "public" | "selfmade"
    difficulty: Difficulty
    title: str
    requirements: str
    # 接口表
    variables: list[VarDef] = field(default_factory=list)
    # 题目是否要求写成 FUNCTION_BLOCK（默认 PROGRAM 也可）
    target_pou: str = "FUNCTION_BLOCK"
    # 形式化规约（LTL）。空表示尚未编写。
    specs: list["Spec"] = field(default_factory=list)
    # 测试用例（扫描周期表）
    test_cases: list["TestCase"] = field(default_factory=list)
    # 出题溯源（自建题必填，公共题可留空）
    provenance: dict[str, Any] = field(default_factory=dict)
    # 原文语言，便于报告中说明"题目为英文、生成代码保持英文标识符"
    language: str = "en"
    # TestCase 未标注 mode 时的缺省值：single | sequence
    case_mode: str = "single"
    # 原始题目全文（保真留档，便于核查解析是否遗漏）
    raw_text: str = ""
    # 有界模型检查的搜索上界。默认值按"被测程序一般 3~6 拍进入稳态"取；
    # 状态多的题（带数组/缓冲区的）要显式调小，否则会撞上 max_traces。
    # 有界模型检查的预算。深度 8 覆盖本项目里最长的性质（`X(X(...))` 加边沿
    # 记忆约 4~6 拍）；轨迹数上限是**工作量闸门**，不是"结论强度"——
    # 撞到它只意味着"预算内没发现违反"，报告里必须显示 truncated。
    mc_max_depth: int = 8
    mc_max_traces: int = 60000
    mc_max_seconds: float = 60.0
    # 输入域。留空时由 driver 从测试用例自动推断（同源，避免两处漂移）
    mc_inputs: dict[str, list[Any]] = field(default_factory=dict)
    # Binding parameters are enumerated across traces, but held fixed within each trace.
    mc_fixed_inputs: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["difficulty"] = self.difficulty.value
        d["variables"] = [v.to_dict() for v in self.variables]
        d["specs"] = [s.to_dict() for s in self.specs]
        d["test_cases"] = [t.to_dict() for t in self.test_cases]
        return d

    @staticmethod
    def from_dict(d: dict[str, Any]) -> "Problem":
        return Problem(
            pid=d["pid"],
            source=d["source"],
            difficulty=Difficulty(d["difficulty"]),
            title=d["title"],
            requirements=d["requirements"],
            variables=[VarDef.from_dict(v) for v in d.get("variables", [])],
            target_pou=d.get("target_pou", "FUNCTION_BLOCK"),
            specs=[Spec.from_dict(s) for s in d.get("specs", [])],
            test_cases=[TestCase.from_dict(t) for t in d.get("test_cases", [])],
            provenance=d.get("provenance", {}) or {},
            language=d.get("language", "en"),
            case_mode=d.get("case_mode", "single") or "single",
            raw_text=d.get("raw_text", ""),
            mc_max_depth=int(d.get("mc_max_depth", 8)),
            mc_max_traces=int(d.get("mc_max_traces", 60000)),
            mc_max_seconds=float(d.get("mc_max_seconds", 60.0)),
            mc_inputs=d.get("mc_inputs", {}) or {},
            mc_fixed_inputs=d.get("mc_fixed_inputs", []) or [],
        )

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(self.to_dict(), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    @staticmethod
    def load(path: Path) -> "Problem":
        return Problem.from_dict(json.loads(path.read_text(encoding="utf-8")))

    # ---- 便捷属性 ----
    @property
    def inputs(self) -> list[VarDef]:
        return [v for v in self.variables if v.direction == Direction.INPUT]

    @property
    def outputs(self) -> list[VarDef]:
        return [v for v in self.variables if v.direction == Direction.OUTPUT]

    @property
    def inouts(self) -> list[VarDef]:
        return [v for v in self.variables if v.direction == Direction.INOUT]


@dataclass
class Spec:
    """一条形式化规约。

    我们同时保存三样东西：
    * ``text``：自然语言陈述（人读、报告用）；
    * ``ltl``：LTL 公式（工具读）；
    * ``kind``：规约类别，决定它能不能被 PLCVerif 之类工具处理。

    分类是刻意的：**安全和顺序类规约可以写成纯布尔 LTL**，而数值/字符串类
    要求（如 IPv4 解析、滑动平均）本质是数据流计算，写成纯 LTL 会丢失信息，
    这类规约我们只在测试用例里覆盖，并在报告中如实说明。
    """

    sid: str
    text: str
    ltl: str = ""
    kind: str = "safety"  # safety | liveness | sequencing | data
    verified_by: str = "plcverif"  # plcverif | simulation | manual

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @staticmethod
    def from_dict(d: dict[str, Any]) -> "Spec":
        return Spec(
            sid=d["sid"],
            text=d["text"],
            ltl=d.get("ltl", ""),
            kind=d.get("kind", "safety"),
            verified_by=d.get("verified_by", "plcverif"),
        )


@dataclass
class TestCase:
    """一条测试用例。

    取值语义（这是评分表里"测试通过率"的口径来源，必须在报告里写清）：

    * ``inputs``       —— 逐周期输入。BOOL 输入必须写；数值输入也可写在这里
      表示"本周期取该值"。
    * ``const_inputs`` —— 全程保持常量的输入（数值数组、设定值等）。
      关键：写在 ``const_inputs`` 里的变量**不会被 inputs 的缺省值覆盖**，
      否则数值输入会被当成 BOOL 清成 0。
    * ``init``         —— 该用例开始时功能块实例的**存储器初值**。
      用来表达"上一周期遗留的状态"（例如输出上一周期是 10.0），
      这样单周期用例也能断言"保持不变"类要求。
    * ``expected``     —— 断言。默认只断言列出的输出。

    ``mode`` 决定这条用例怎么跑：
    * ``single``   —— 每条用例一个全新实例，和别的用例互不影响；
    * ``sequence`` —— 与同 mode 的其他用例**串成一条连续轨迹**，
      因为它们的 ``tc_id`` 顺序就是扫描周期顺序。

    ``expect_full=True`` 表示**所有输出**都必须给期望值（用于"输出冻结"
    类要求，避免只挑一个输出断言而漏掉别的被误改写）。
    """

    tc_id: str
    inputs: dict[str, Any]
    expected: dict[str, Any]
    note: str = ""
    const_inputs: dict[str, Any] = field(default_factory=dict)
    init: dict[str, Any] = field(default_factory=dict)
    # single | sequence（空 = 用 Problem.case_mode）
    mode: str = ""
    # sequence 模式下这条用例连续跑几个扫描周期（默认 1）
    cycles: int = 1
    expect_full: bool = False
    group: str = ""
    expected_any: list[dict[str, Any]] = field(default_factory=list)
    scan_interval_ms: int | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @staticmethod
    def from_dict(d: dict[str, Any]) -> "TestCase":
        return TestCase(
            tc_id=d["tc_id"],
            inputs=d.get("inputs", {}),
            expected=d.get("expected", {}),
            note=d.get("note", ""),
            const_inputs=d.get("const_inputs", {}),
            init=d.get("init", {}) or {},
            mode=d.get("mode", "") or "",
            cycles=int(d.get("cycles", 1) or 1),
            expect_full=bool(d.get("expect_full", False)),
            group=d.get("group", "") or "",
            expected_any=d.get("expected_any", []),
            scan_interval_ms=d.get("scan_interval_ms"),
        )


@dataclass
class RunResult:
    """一次完整运行的结果，是实验分析的唯一原始依据。"""

    pid: str
    framework: str  # "baseline" | "selfmade"
    model: str  # 模型 id，如 "claude-opus-5-5"
    provider: str = ""
    # 生成
    attempts: int = 0  # 总共尝试了几版代码（首版 + 修复次数）
    first_compile_ok: bool = False
    final_compile_ok: bool = False
    compile_errors: list[dict[str, Any]] = field(default_factory=list)
    # 测试
    tests_total: int = 0
    tests_passed: int = 0
    # 规约
    specs_total: int = 0
    specs_passed: int = 0
    specs_timeout: int = 0
    # 资源
    prompt_tokens: int = 0
    completion_tokens: int = 0
    wall_seconds: float = 0.0
    est_cost_usd: float = 0.0
    # 产物
    code: str = ""
    run_dir: str = ""
    error: str = ""

    @property
    def first_compile_rate(self) -> float:
        return 1.0 if self.first_compile_ok else 0.0

    @property
    def final_compile_rate(self) -> float:
        return 1.0 if self.final_compile_ok else 0.0

    @property
    def test_pass_rate(self) -> float:
        if self.tests_total == 0:
            return 0.0
        return self.tests_passed / self.tests_total

    @property
    def spec_pass_rate(self) -> float:
        if self.specs_total == 0:
            return 0.0
        return self.specs_passed / self.specs_total

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
