"""ST 验证流水线的统一入口（"编译器对外的那张脸"）。

上层（benchmark runner、自研 harness、模型的修复循环）只认这几样东西：

* ``check_st(src)``       —— 编译代理，返回诊断
* ``simulate(...)``       —— 扫描周期仿真，返回逐周期比对结果
* ``verify(src, problem)`` —— 一次跑完检查 + 全部测试用例

设计要点：**验证层必须比被测代码稳定**。模型生成的 ST 千变万化，但验证入口
只有几个函数，出问题时能立刻判断是验证器有 bug 还是生成代码有 bug。

关于两种用例模式（这是最容易搞混、也是评分表里"测试通过率"口径的来源）
------------------------------------------------------------------------
* ``mode="single"``：**每个用例独立起一个全新的功能块实例**跑 1 个周期。
  断言的是"给定这一组输入，这一周期输出应为多少"。适合组合逻辑。
  注意：跨周期保持类断言（例如"enable=FALSE 时保持上一周期输出"）在单周期
  模式下只能靠**该用例自己的 ``init`` 初值**来表达，不能靠"上一条用例"。
* ``mode="sequence"``：**用例按顺序组成一条连续轨迹**，状态跨周期保留。
  适合状态机、边沿检测、FIFO、计时器这类时序题。

一个 ``Problem`` 里可以同时有这两种用例：``TestCase.mode`` 逐条标注，
``Problem.case_mode`` 给缺省值。这样同一道题既能测"输入→输出"的映射，
又能测"连续扫描下的行为"，不必二选一。

CLI，手工验一把：
    python -m stbench.st.driver --src path/to/fb.st --problem datasets/selfmade/self-easy-01.json
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from ..schema import Problem, TestCase
from .frontend import CompileResult, compile_st
from .interp import (
    ArrayValue,
    Interpreter,
    SimError,
    SimOutcome,
    SimulationTimeout,
    StructValue,
    _match,
    simulate,
)
from .typecheck import check_st, typecheck

__all__ = [
    "check_st",
    "simulate",
    "verify",
    "StageResult",
    "CaseResult",
    "CompileResult",
    "SimOutcome",
]


@dataclass
class CaseResult:
    """单个测试用例的结果。"""

    tc_id: str
    passed: bool
    message: str = ""
    mode: str = "single"
    expected: dict[str, Any] = field(default_factory=dict)
    actual: dict[str, Any] = field(default_factory=dict)
    # 失败时给 harness 看的一句"为什么错"，是自动修复循环的输入
    hint: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "tc_id": self.tc_id,
            "passed": self.passed,
            "mode": self.mode,
            "message": self.message,
            "expected": _plain(self.expected),
            "actual": _plain(self.actual),
            "hint": self.hint,
        }


@dataclass
class StageResult:
    """一段代码的完整验证结果。"""

    compiles: bool
    compile_errors: list[dict[str, Any]] = field(default_factory=list)
    tests_total: int = 0
    tests_passed: int = 0
    cases: list[CaseResult] = field(default_factory=list)
    failure_summary: str = ""
    # 第三层：有界模型检查（LTL）。与测试分开记，口径不能混。
    mc_states: int = 0
    mc_traces: int = 0
    mc_specs_total: int = 0
    mc_specs_hold: int = 0
    mc_specs_violated: int = 0
    mc_specs_inconclusive: int = 0
    mc_violations: list[dict[str, Any]] = field(default_factory=list)
    mc_error: str = ""
    # 撞到深度/迁移预算：结论只能是"预算内未发现违反"，不能写成"已验证"。
    mc_truncated: bool = False
    mc_executed: bool = False
    mc_fixed_input_domains: dict[str, list[Any]] = field(default_factory=dict)
    platform_results: dict[str, Any] = field(default_factory=dict)
    evidence_metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def specs_all_hold(self) -> bool:
        """规约是否全部成立（有界内）。

        注意：这是"有界成立"，不等于数学证明——报告里必须这么写。
        """
        return self.mc_executed and not self.mc_error and not self.mc_truncated and self.mc_specs_total > 0 and self.mc_specs_violated == 0 and self.mc_specs_inconclusive == 0

    @property
    def all_tests_passed(self) -> bool:
        return self.tests_total > 0 and self.tests_passed == self.tests_total

    @property
    def pass_rate(self) -> float:
        return self.tests_passed / self.tests_total if self.tests_total else 0.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "compiles": self.compiles,
            "compile_errors": _plain(self.compile_errors),
            "tests_total": self.tests_total,
            "tests_passed": self.tests_passed,
            "pass_rate": round(self.pass_rate, 4),
            "failure_summary": self.failure_summary,
            "cases": [c.to_dict() for c in self.cases],
            "model_check": {
                "states": self.mc_states,
                "traces": self.mc_traces,
                "specs_total": self.mc_specs_total,
                "specs_hold": self.mc_specs_hold,
                "specs_violated": self.mc_specs_violated,
                "specs_inconclusive": self.mc_specs_inconclusive,
                "violations": _plain(self.mc_violations),
                "error": self.mc_error,
                "truncated": self.mc_truncated,
                "executed": self.mc_executed,
                "fixed_input_domains": _plain(self.mc_fixed_input_domains),
            },
            "platform_results": self.platform_results,
            "evidence_metadata": self.evidence_metadata,
        }


def _plain(obj: Any) -> Any:
    """把仿真值转成可 JSON 序列化的普通结构。"""
    if isinstance(obj, ArrayValue):
        return [_plain(x) for x in obj.items]
    if isinstance(obj, StructValue):
        return {k: _plain(v) for k, v in obj.values.items()}
    if isinstance(obj, dict):
        return {str(k): _plain(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_plain(x) for x in obj]
    if isinstance(obj, bool) or obj is None or isinstance(obj, (int, float, str)):
        return obj
    return str(obj)


def _outputs_of(problem: Problem) -> list[str]:
    return [v.name for v in problem.outputs] + [v.name for v in problem.inouts]


def _compile_errors(src: str) -> tuple[bool, list[dict[str, Any]], str]:
    res = check_st(src)
    errors = [d.to_dict() for d in res.diags if d.level == "error"]
    if res.pou is None:
        errors.append({"code":"E_NO_POU","line":0,"message":"未找到可执行 POU"})
        return False, errors, "未找到可执行 POU"
    if res.ok:
        return True, [], ""
    summary = "静态检查未通过：" + "; ".join(
        f"[{e.get('code', 'E')}] 第{e.get('line', 0)}行 {e.get('message', '')}"
        for e in errors[:3]
    )
    return False, errors, summary


def _run_case(src: str, problem: Problem, tc: TestCase, mode: str) -> CaseResult:
    """跑单条用例（``single`` 模式：一个全新实例，不带上一条用例的副作用）。"""
    res = typecheck(compile_st(src))
    if res.pou is None:
        return CaseResult(tc.tc_id, False, message="没有可仿真的 POU", mode=mode)

    interp = Interpreter(res.pou, res.structs)

    # 1) 初值：用例自带 init -> 模拟"实例上电前的存储器状态"
    for k, v in (tc.init or {}).items():
        try:
            interp.set_var(k, v)
        except SimError as e:
            return CaseResult(tc.tc_id, False, message=f"初值 {k} 无法写入：{e}", mode=mode)

    # 2) 常量输入 / 逐周期输入
    vec = {k.lower(): v for k, v in (tc.inputs or {}).items()}
    const = {k.lower(): v for k, v in (tc.const_inputs or {}).items()}
    for k, v in const.items():
        try:
            interp.set_var(k, v)
        except SimError as e:
            return CaseResult(
                tc.tc_id, False, message=f"常量输入 {k} 无法写入：{e}", mode=mode
            )
    for name in [v.name for v in problem.inputs]:
        low = name.lower()
        if low in vec:
            interp.set_var(name, vec[low])
        elif low in const:
            continue  # 保持常量
        elif interp.types.get(low, "").upper() == "BOOL":
            interp.set_var(name, False)

    # 3) 跑 1..n 个周期
    cycles = max(1, int(tc.cycles or 1))
    try:
        for _ in range(cycles):
            interp.scan()
    except SimulationTimeout as e:
        return CaseResult(tc.tc_id, False, message=f"仿真超时：{e}", mode=mode)
    except SimError as e:
        return CaseResult(
            tc.tc_id, False, message=f"运行期错误（第{e.line}行）：{e}", mode=mode
        )

    # 4) 断言
    actual: dict[str, Any] = {}
    expects: dict[str, Any] = {}
    outs = _outputs_of(problem)
    if tc.expect_full:
        missing = [o for o in outs if o.lower() not in {k.lower() for k in tc.expected}]
        if missing:
            return CaseResult(
                tc.tc_id,
                False,
                message=f"用例标注 expect_full 但缺少输出 {missing} 的期望值",
                mode=mode,
            )
        pairs = [(o, tc.expected[o]) for o in outs]
    else:
        pairs = list(tc.expected.items())

    for name, exp in pairs:
        if name.lower() not in interp.mem:
            return CaseResult(tc.tc_id, False, message=f"接口里没有输出 {name}", mode=mode)
        got = interp.get_var(name)
        actual[name] = got
        expects[name] = exp
        if not _match(got, exp):
            return CaseResult(
                tc.tc_id,
                False,
                message=f"{name} 期望 {_plain(exp)!r}，实际 {_plain(got)!r}",
                mode=mode,
                expected=expects,
                actual=actual,
                hint=f"{tc.tc_id}（{tc.note}）: {name} 期望 {_plain(exp)!r}，实际 {_plain(got)!r}",
            )

    return CaseResult(tc.tc_id, True, mode=mode, expected=expects, actual=actual)


def verify(src: str, problem: Problem, *, model_check: bool = True) -> StageResult:
    """对一道题跑完整验证：编译 → 逐条用例 → 有界模型检查。

    三层对应课件 S1_1 第 13 页的正确性层次：

    * 语法 + 静态语义（编译器）——只查第 1、2 层；
    * 操作语义（测试）——查少数几条手挑的轨迹；
    * 模型检查（LTL）——查**模型的全部轨迹**，这是唯一能说"没违反"的一层，
      但结论是**有界**的（见 ``stbench.modelcheck`` 顶部的说明）。

    三者指标必须分开记：测试通过率不等于规约成立，混在一起论文就没法自圆其说。
    """
    ok, errors, summary = _compile_errors(src)
    out = StageResult(compiles=ok, compile_errors=errors)
    if not ok:
        out.failure_summary = summary
        return out

    if not problem.test_cases:
        out.failure_summary = "该题尚未编写测试用例"
        return out

    out.tests_total = len(problem.test_cases)
    for tc in problem.test_cases:
        mode = tc.mode or problem.case_mode
        case = _run_case(src, problem, tc, mode)
        out.cases.append(case)
        if case.passed:
            out.tests_passed += 1
        elif not out.failure_summary:
            out.failure_summary = f"{tc.tc_id}: {case.message}"

    if model_check:
        _attach_model_check(src, problem, out)
    return out


def _attach_model_check(src: str, problem: Problem, out: StageResult) -> None:
    """跑有界模型检查并把结果并进 StageResult。

    输入空间从**测试用例里出现过的取值**自动收集：这样不用给每道题再手写一份
    输入域，而且保证"检查的范围"和"测试覆盖的范围"是同源的，不会出现
    "测试用的值模型检查里压根没枚举过"这种自相矛盾。
    """
    from ..modelcheck import InputSpace, check as mc_check
    out.mc_executed = True

    specs = [(sp.sid, sp.ltl) for sp in problem.specs if sp.ltl.strip()]
    if not specs:
        out.mc_error = "该题没有可执行的 LTL 规约"
        return

    if any(v.data_type.upper()=="VARIANT" for v in problem.variables):
        out.mc_specs_total=len(specs)
        out.mc_specs_inconclusive=len(specs)
        out.mc_error="Unsupported modeling: generic VARIANT caller binding is not quantified; zero-capacity default would be vacuous"
        return
    try:
        domains = _collect_domains(problem)
    except (TypeError,ValueError) as exc:
        out.mc_error="Invalid input-domain configuration: "+str(exc)
        return
    if not domains:
        out.mc_error = "无法从用例推断输入域"
        return

    try:
        rep = mc_check(
            src,
            specs,
            InputSpace(domains,tuple(problem.mc_fixed_inputs)),
            max_depth=problem.mc_max_depth,
            max_traces=problem.mc_max_traces,
            max_seconds=problem.mc_max_seconds,
            program_name=problem.pid,
        )
    except Exception as e:  # 检查器自身出错不能污染"程序对不对"的结论
        out.mc_error = f"模型检查器异常：{type(e).__name__}: {e}"
        return

    if rep.error:
        out.mc_error = rep.error
        return

    out.mc_states = rep.states_explored
    out.mc_fixed_input_domains=rep.fixed_input_domains
    out.mc_traces = rep.traces_explored
    out.mc_truncated = rep.truncated
    out.mc_specs_total = len(rep.specs)
    for s in rep.specs:
        if s.contradicting:
            out.mc_specs_violated += 1
            out.mc_violations.append(
                {
                    "id": s.spec_id,
                    "formula": s.formula,
                    "at": s.ce_at,
                    "explanation": s.explanation,
                    "trace": s.counterexample,
                }
            )
        elif s.inconclusive:
            out.mc_specs_inconclusive += 1
        elif s.holds:
            out.mc_specs_hold += 1


def verify_sequence(src: str, problem: Problem, mode: str = "sequence", *, model_check: bool = False) -> StageResult:
    """把同一 mode 的用例**按时间顺序**串成一条轨迹跑（状态跨用例保留）。

    ``verify`` 是"每条用例一个新实例"，本函数补上"连续扫描"的那一半：
    状态机、FIFO、计时器这类题目必须在连续轨迹下才测得出真实行为。

    为什么不一次性 ``simulate`` 到底
    --------------------------------
    初版把所有向量合并成一条轨迹、用 ``const.update`` 合并常量输入，结果是
    **后一个周期的常量会覆盖前一个周期的**：self-easy-02 的 ``resetBtn``
    全部变成 False、self-medium-02 的 ``enable`` 最后变成 False——轨迹整体
    走样，报出来的失败点也就不足为信。

    更重要的是**失败定位**：真实轨迹里第 2 个周期失败时，后面周期的断言
    依然可能成立（对象状态本来就不同）。所以这里逐周期推进，每一周期都用
    **当时的常量**覆盖写入，断言该周期，然后无论成败都继续——这样"用例
    通过数"才是真实通过数，而不是"从第一个失败点之后全算失败"。

    一个附带的好处：多条轨迹可以叠加在同一个应用轨迹里，模拟"操作员先
    正常灌装，然后故意乱按按钮"这种真实扰乱场景。
    """
    ok, errors, summary = _compile_errors(src)
    out = StageResult(compiles=ok, compile_errors=errors)
    if not ok:
        out.failure_summary = summary
        return out

    traj = [tc for tc in problem.test_cases if (tc.mode or problem.case_mode) == mode]
    if not traj:
        out.failure_summary = f"没有 mode={mode} 的用例"
        return out
    out.tests_total = len(traj)

    result = typecheck(compile_st(src))
    if result.pou is None:
        out.failure_summary = "没有可仿真的 POU"
        return out
    interp = Interpreter(result.pou, result.structs)
    in_names = [v.name for v in problem.inputs]
    outs = _outputs_of(problem)

    first_fail: str = ""
    for tc in traj:
        vec = {k.lower(): v for k, v in (tc.inputs or {}).items()}
        const = {k.lower(): v for k, v in (tc.const_inputs or {}).items()}
        try:
            for k, v in (tc.init or {}).items():
                interp.set_var(k, v)
            # 常量先写：本周期没显式给值的输入一律沿用它的"当前工程值"
            for k, v in const.items():
                interp.set_var(k, v)
            for name in in_names:
                low = name.lower()
                if low in vec:
                    interp.set_var(name, vec[low])
                elif low in const:
                    continue
                elif interp.types.get(low, "").upper() == "BOOL":
                    interp.set_var(name, False)
            for _ in range(max(1, int(tc.cycles or 1))):
                interp.scan()
        except SimulationTimeout as e:
            case = CaseResult(tc.tc_id, False, mode=mode, message=f"仿真超时：{e}")
            out.cases.append(case)
            first_fail = first_fail or f"{tc.tc_id}: {case.message}"
            break
        except SimError as e:
            case = CaseResult(
                tc.tc_id, False, mode=mode,
                message=f"运行期错误（第{e.line}行）：{e}",
            )
            out.cases.append(case)
            first_fail = first_fail or f"{tc.tc_id}: {case.message}"
            break

        got: dict[str, Any] = {}
        want: dict[str, Any] = {}
        bad_msg = ""
        for name, exp in (tc.expected or {}).items():
            if name.lower() not in interp.mem:
                bad_msg = f"接口里没有输出 {name}"
                break
            got[name] = interp.get_var(name)
            want[name] = exp
            if not _match(got[name], exp):
                bad_msg = (f"{name} 期望 {_plain(exp)!r}，实际 {_plain(got[name])!r}")
                break
        if bad_msg:
            case = CaseResult(
                tc.tc_id, False, mode=mode, message=bad_msg,
                expected=want, actual=got,
                hint=f"{tc.tc_id}（{tc.note}）：{bad_msg}",
            )
            out.cases.append(case)
            first_fail = first_fail or f"{tc.tc_id}: {bad_msg}"
        else:
            out.cases.append(CaseResult(tc.tc_id, True, mode=mode, expected=want, actual=got))

    out.tests_passed = sum(1 for c in out.cases if c.passed)
    out.failure_summary = first_fail
    if model_check:
        _attach_model_check(src, problem, out)
    return out


# 老名字保留，免得旧脚本引用失败
verify_multicycle = verify_sequence


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="验证一份 ST 代码")
    ap.add_argument("--src", type=Path, required=True, help="ST 源码文件")
    ap.add_argument("--problem", type=Path, help="题目 JSON（不给则只做静态检查）")
    ap.add_argument("--json", action="store_true", help="以 JSON 输出")
    ap.add_argument(
        "--only", default="", help="只跑给定 mode 的用例（single/sequence）"
    )
    args = ap.parse_args(argv)

    src = args.src.read_text(encoding="utf-8")

    if args.problem is None:
        res = check_st(src)
        if args.json:
            print(json.dumps(res.to_dict(), ensure_ascii=False, indent=2))
        else:
            print("通过静态检查" if res.ok else "静态检查未通过")
            for d in res.diags:
                print(" ", d)
        return 0 if res.ok else 1

    problem = Problem.load(args.problem)
    if args.only:
        for mode in ("single", "sequence"):
            if mode != args.only:
                continue
            out = verify(src, problem) if mode == "single" else verify_sequence(src, problem)
    else:
        out = verify(src, problem)

    if args.json:
        print(json.dumps(out.to_dict(), ensure_ascii=False, indent=2))
    else:
        print(f"编译：{'通过' if out.compiles else '失败'}")
        print(f"用例：{out.tests_passed}/{out.tests_total}")
        for c in out.cases:
            print(f"  [{'PASS' if c.passed else 'FAIL'}] {c.tc_id} ({c.mode}) {c.message}")
        if out.failure_summary and not out.all_tests_passed:
            print(f"首个失败：{out.failure_summary}")
    return 0 if out.all_tests_passed else 1


if __name__ == "__main__":
    sys.exit(main())

def _collect_domains(problem) -> dict[str, list]:
    """从测试用例里收集每个输入出现过的取值，作为模型检查的输入域。

    为什么从用例推断而不是另写一份：两处独立维护必然漂移，一旦"测试里用过的值
    模型检查没枚举"，结论就不可信了。同源才能互证。

    BOOL 输入不满两种取值时补全成 ``[False, True]``——否则"没给的那一支"会被
    当成不可能，把反例挡在门外（这是最隐蔽的假绿）。
    """
    seen: dict[str, list] = {}

    # 模型检查的输入空间只认 VAR_INPUT：VAR_IN_OUT（尤其结构体数组）没法穷举，
    # ``tc.init`` 里喂给它们的初值是"用例侧固定的先验条件"，不是可自由取值的输入。
    # 不收进来，否则 InputSpace.validate 会报"输入域里这些名字在程序中不存在"，
    # 整个 MC 一拍都不展。输入接口为空的病态题也退化为不过滤（保持旧行为）。
    allowed = {
        d.name.lower()
        for d in (problem.variables or [])
        # direction 是枚举（Direction.INPUT），取最后一段再比，别整体小写
        if str(getattr(d, "direction", "input")).rsplit(".", 1)[-1].lower() == "input"
    }

    def _add(d: dict) -> None:
        for k, v in (d or {}).items():
            if str(k).startswith("_"):
                continue
            name = str(k).lower()
            if allowed and name not in allowed:
                continue
            vals = seen.setdefault(name, [])
            if v not in vals:
                vals.append(v)

    for tc in problem.test_cases:
        # inputs 在 sequence 模式下是"逐周期列表"，单周期是 dict。两种都收。
        inp = tc.inputs
        if isinstance(inp, list):
            for step in inp:
                _add(step)
        else:
            _add(inp)
        _add(tc.const_inputs)
        _add(tc.init)

    types = {d.name.lower(): d.data_type.upper() for d in (problem.variables or [])}
    out: dict[str, list] = {}
    for name, vals in seen.items():
        if types.get(name) == "BOOL" and set(vals) <= {True, False}:
            out[name] = [False, True]
        elif len(vals) == 1:
            # 单值输入：BOOL 已在上游补全；数值扩到相邻取值，
            # 否则模型检查把它当常量，状态图只有一条线。
            v = vals[0]
            if isinstance(v, bool):
                out[name] = [False, True]
            elif isinstance(v, int):
                out[name] = sorted({v, v + 1, max(v - 1, 0)})
            elif isinstance(v, float):
                out[name] = sorted({v, v + 1.0, max(v - 1.0, 0.0)})
            else:
                out[name] = vals
        else:
            out[name] = vals
    for name,values in (problem.mc_inputs or {}).items():
        key=name.lower()
        if key not in allowed or not isinstance(values,list) or not values:
            raise ValueError("MC domain must name a declared input and contain a nonempty list")
        out[key]=values
    return out
