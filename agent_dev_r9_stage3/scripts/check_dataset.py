"""公共题数据集自检工具（成员 1 专用）。

为什么需要这个脚本
------------------
20 道公共题现在 ``specs`` 和 ``test_cases`` **全是空的**。补这两样东西时，
最容易犯的错是"看起来对、实际自相矛盾"——比如断言期望 ``highHigh=True``
却从没制造让传感器失效的那个转移。这类错误肉眼查不出来，但会让模型
写对了也被判错。

自建题当初就是靠"写参考解 + 本机跑通"抓出了 2 个真 bug。这个脚本把
那道闸门给公共题也装上。

用法
----
    # 体检：看 20 道题各自缺什么
    python -X utf8 scripts/check_dataset.py

    # 只体检某一道
    python -X utf8 scripts/check_dataset.py --pid public-easy-01

    # 验证某个参考解能不能跑通这道题的全部用例
    python -X utf8 scripts/check_dataset.py --pid public-easy-01 \\
        --ref datasets/public/tests/public-easy-01.reference.st

    # 校验一条 LTL 规约的语法（不需要参考解）
    python -X utf8 scripts/check_dataset.py --ltl "G(count >= 0 & count <= 8)"

    # 拿现存的自建题做回归，确认工具本身没坏
    python -X utf8 scripts/check_dataset.py --selfmade
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from stbench.schema import Problem  # noqa: E402

PUBLIC_DIR = ROOT / "datasets" / "public"
SELFMADE_DIR = ROOT / "datasets" / "selfmade"

# 规约里允许出现的算子。超出这个集合说明写法不被支持，
# 与其等到跑实验时报错，不如现在就拦住。
ALLOWED_FUNCS = {"G", "F", "X", "U", "prev", "no_array_overflow", "rising", "falling"}


def _dir_name(d) -> str:
    v = getattr(d, "value", d)
    return {"input": "输入", "output": "输出", "inout": "输入输出", "local": "内部"}.get(str(v), str(v))


def audit_problem(p: Problem) -> tuple[list[str], list[str]]:
    """返回 (硬性问题, 提醒)。硬性问题存在时，这道题不能进实验。"""
    hard: list[str] = []
    warn: list[str] = []

    if not p.specs:
        hard.append("没有 LTL 规约（specs 为空）")
    if not p.test_cases:
        hard.append("没有测试用例（test_cases 为空）")

    # ---- 用例自洽性 ----
    if p.test_cases:
        names_in = {v.name for v in p.variables if _dir_name(v.direction) == "输入"}
        names_out = {v.name for v in p.variables if _dir_name(v.direction) == "输出"}
        declared = {v.name for v in p.variables}

        used_in, used_out = set(), set()
        for c in p.test_cases:
            used_in |= set(c.inputs or {}) | set(c.const_inputs or {})
            used_out |= set(c.expected or {})

        unknown = (used_in | used_out) - declared
        if unknown:
            hard.append(f"用例用了接口没声明的变量：{sorted(unknown)}")

        missing_in = names_in - used_in
        if missing_in:
            warn.append(f"这些输入变量从没在用例里出现：{sorted(missing_in)}（可能是漏测）")
        missing_out = names_out - used_out
        if missing_out:
            hard.append(f"这些输出变量从没被断言过：{sorted(missing_out)}（漏测 = 模型写错也发现不了）")

        # single 模式的初值幻觉：新实例初值只能是 0/FALSE
        empty_exp = [c.tc_id for c in p.test_cases if not (c.expected or {})]
        if empty_exp:
            hard.append(f"这些用例没有任何期望值：{empty_exp[:5]}")

        # 用例 id 不能重复
        ids = [c.tc_id for c in p.test_cases]
        dup = {i for i in ids if ids.count(i) > 1}
        if dup:
            warn.append(f"用例 id 重复：{sorted(dup)}（同一 id 的周期会被合并成一条轨迹）")

    # ---- 规约形态 ----
    for s in p.specs:
        # verified_by=simulation 的条目是**故意**没有 LTL 的（数据类性质，
        # 例如"avgOut 等于所选样本的算术平均"，跨多行语句，LTL 只能逐原子
        # 表达、写出来反而比用例更难读）。这类不该判红。
        if not s.ltl:
            if (s.verified_by or "") == "simulation":
                continue
            hard.append(f"{s.sid} 有 text 但没有 ltl 表达式（也没标 verified_by=simulation）")
            continue
        if not any(f in s.ltl for f in ALLOWED_FUNCS):
            warn.append(f"{s.sid} 不含任何时序算子（G/F/X/U），它其实是个不变式检查：{s.ltl}")
        # 只在**顶层**用 prev（不带 G）才是真问题：表达式只判第 1 拍，
        # 而 prev 在第 1 拍无定义 → 恒不可判定。
        # 反过来 "G(p -> x = prev(x))" 是本项目的标准写法（同拍语义 = 与上一拍
        # 比较），不需要再套一层 X，所以不再对"prev 但没有 X"警告。
        if "prev(" in s.ltl and "G(" not in s.ltl:
            warn.append(f"{s.sid} 在 G 之外用了 prev，第 1 拍无定义，可能恒不可判定：{s.ltl}")
        if not s.verified_by:
            warn.append(f"{s.sid} 没填 verified_by")

    return hard, warn


def check_ltl(expr: str) -> list[str]:
    """单独校验一条 LTL 表达式的形态（不依赖题目）。"""
    out: list[str] = []
    if not expr.strip():
        return ["表达式为空"]
    if not any(f in expr for f in ALLOWED_FUNCS):
        out.append(f"不含任何时序算子（G/F/X/U），它其实是个不变式检查：{expr}")
    if expr.count("(") != expr.count(")"):
        out.append(f"括号不配对：{expr}")
    # 常见笔误：把相等写成单个 =，那是赋值不是比较
    import re as _re
    if _re.search(r"(?<![<>!=])=(?!=)", expr):
        out.append(f"出现了单个 '='，ST 里判等是 '=' 但 LTL 里请确认是不是想写 '='（比较）而非赋值")
    return out


def report(problems: list[Problem], title: str) -> int:
    print(f"\n{'=' * 66}")
    print(f"{title}（共 {len(problems)} 道）")
    print(f"{'=' * 66}")

    ok_cnt = 0
    for p in problems:
        hard, warn = audit_problem(p)
        status = "✅" if not hard else "❌"
        if not hard:
            ok_cnt += 1
        print(f"\n{status} {p.pid}  {p.title}")
        print(f"   规约 {len(p.specs)} 条 | 用例 {len(p.test_cases)} 条 | 变量 {len(p.variables)} 个")
        for h in hard:
            print(f"   ✗ {h}")
        for w in warn:
            print(f"   ! {w}")

    print(f"\n{'─' * 66}")
    print(f"可以进实验的题：{ok_cnt}/{len(problems)}")
    return 0 if ok_cnt == len(problems) else 1


def verify_ref(pid: str, ref_path: Path) -> int:
    """把参考解跑一遍这道题的全部用例。"""
    from stbench.st.driver import verify, verify_sequence

    f = PUBLIC_DIR / f"{pid}.json"
    if not f.exists():
        f = SELFMADE_DIR / f"{pid}.json"
    if not f.exists():
        print(f"找不到题目 {pid}", file=sys.stderr)
        return 2

    p = Problem.load(f)
    code = ref_path.read_text(encoding="utf-8")

    if not p.test_cases:
        print(f"{pid} 还没有测试用例，先补用例再验参考解")
        return 1

    if p.case_mode == "sequence":
        res = verify_sequence(code, p)
    else:
        res = verify(code, p)

    print(f"\n{pid} 参考解验证")
    print(f"  编译：{'通过' if res.compiles else '失败'}")
    if not res.compiles:
        for d in res.compile_errors:
            print(f"    {d}")
        return 1
    print(f"  用例：{res.tests_passed}/{res.tests_total} 通过")
    failures = [c.message for c in res.cases if not c.passed]
    if failures:
        print("  失败明细（最多 5 条）：")
        for line in failures[:5]:
            print(f"    {line}")
    return 0 if res.all_tests_passed else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="公共题数据集自检")
    ap.add_argument("--pid", help="只检查某一道题")
    ap.add_argument("--ref", type=Path, help="配合 --pid 验证参考解")
    ap.add_argument("--ltl", help="校验一条 LTL 表达式的形态")
    ap.add_argument("--selfmade", action="store_true", help="对当前全部自建题做回归")
    args = ap.parse_args()

    if args.ltl:
        print(f"表达式：{args.ltl}")
        problems = check_ltl(args.ltl)
        for w in problems:
            print(f"  ✗ {w}")
        if not problems:
            print("  ✅ 形态没问题")
        return 0 if not problems else 1

    if args.pid and args.ref:
        return verify_ref(args.pid, args.ref)

    if args.selfmade:
        fs = sorted(SELFMADE_DIR.glob("self-*.json"))
        return report([Problem.load(f) for f in fs], "自建题回归（这些应该全绿）")

    fs = sorted(PUBLIC_DIR.glob("public-*.json"))
    ps = [Problem.load(f) for f in fs]
    if args.pid:
        ps = [p for p in ps if p.pid == args.pid]
    return report(ps, "公共题数据集体检")


if __name__ == "__main__":
    sys.exit(main())
