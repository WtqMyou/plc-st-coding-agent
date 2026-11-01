"""验证器自测：用"已知正确/已知错误"的 ST 检验检查器本身。

为什么要写这个
--------------
验证器如果自己有 bug，整份实验数据就全是假的——比没做实验更糟。
所以每一类语义都配一对样例：一段应当通过的、一段应当被拦下的。

跑法：
    python -m pytest tests -q          （装了 pytest）
    python tests/test_verifier.py      （直接跑，不需要 pytest）
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stbench.st.interp import simulate  # noqa: E402
from stbench.st.typecheck import check_st  # noqa: E402

CASES: list[tuple[str, str, bool, str]] = []


def case(name: str, src: str, should_pass: bool, why: str) -> None:
    CASES.append((name, src, should_pass, why))


# ---------------------------------------------------------------- 1. 基本赋值
case(
    "basic_assign",
    """
FUNCTION_BLOCK FB
VAR_INPUT a : INT; END_VAR
VAR_OUTPUT b : INT; END_VAR
b := a + 1;
END_FUNCTION_BLOCK
""",
    True,
    "最简单的赋值",
)

# ------------------------------------------------- 2. 给 VAR_INPUT 赋值必须报错
case(
    "write_input_forbidden",
    """
FUNCTION_BLOCK FB
VAR_INPUT a : BOOL; END_VAR
VAR_OUTPUT b : BOOL; END_VAR
a := TRUE;
b := a;
END_FUNCTION_BLOCK
""",
    False,
    "VAR_INPUT 在 FB 内部只读",
)

# ------------------------------------------------------ 3. 大小写不敏感（IEC 规定）
case(
    "case_insensitive",
    """
FUNCTION_BLOCK FB
VAR_INPUT Start : BOOL; END_VAR
VAR_OUTPUT Run : BOOL; END_VAR
Run := start;
END_FUNCTION_BLOCK
""",
    True,
    "start 与 Start 是同一变量",
)

# ------------------------------------------------------ 4. 未声明标识符必须拦下
case(
    "undeclared",
    """
FUNCTION_BLOCK FB
VAR_INPUT a : BOOL; END_VAR
VAR_OUTPUT b : BOOL; END_VAR
b := a AND notDeclaredVar;
END_FUNCTION_BLOCK
""",
    False,
    "拼错的变量名",
)

# ------------------------------------------------------------ 5. 条件类型必须是 BOOL
case(
    "cond_type",
    """
FUNCTION_BLOCK FB
VAR_INPUT n : INT; END_VAR
VAR_OUTPUT b : BOOL; END_VAR
IF n THEN
    b := TRUE;
END_IF;
END_FUNCTION_BLOCK
""",
    False,
    "INT 不能直接当条件",
)

# ------------------------------------------------------------ 6. 逻辑运算操作数
case(
    "logic_operand",
    """
FUNCTION_BLOCK FB
VAR_INPUT n : INT; a : BOOL; END_VAR
VAR_OUTPUT b : BOOL; END_VAR
b := a AND n;
END_FUNCTION_BLOCK
""",
    False,
    "AND 的右操作数是 INT",
)

# ---------------------------------------------------- 7. 结构体字段拼错必须拦下
case(
    "struct_field_typo",
    """
TYPE ST_Pump :
STRUCT
    priority : INT;
    RunComd : BOOL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT pumps : ARRAY[1..5] OF ST_Pump; END_VAR
VAR_OUTPUT ok : BOOL; END_VAR
ok := pumps[1].RunCmd;
END_FUNCTION_BLOCK
""",
    False,
    "RunCmd 应为 RunComd",
)

# ------------------------------------------------ 8. 数组下标越界（常量可静态查出）
case(
    "array_range",
    """
FUNCTION_BLOCK FB
VAR_INPUT arr : ARRAY[1..5] OF INT; END_VAR
VAR_OUTPUT v : INT; END_VAR
v := arr[9];
END_FUNCTION_BLOCK
""",
    False,
    "下标 9 超出 [1..5]",
)

# ------------------------------------------------------------- 9. 缺 END_IF
case(
    "missing_end_if",
    """
FUNCTION_BLOCK FB
VAR_INPUT a : BOOL; END_VAR
VAR_OUTPUT b : BOOL; END_VAR
IF a THEN
    b := TRUE;
END_FUNCTION_BLOCK
""",
    False,
    "IF 没有闭合",
)

# --------------------------------------------------- 10. 类型不匹配（REAL <- BOOL）
case(
    "type_mismatch",
    """
FUNCTION_BLOCK FB
VAR_INPUT a : BOOL; END_VAR
VAR_OUTPUT r : REAL; END_VAR
r := a;
END_FUNCTION_BLOCK
""",
    False,
    "BOOL 不能直接赋给 REAL",
)

# ------------------------------------------------- 11. INT -> REAL 隐式转换是允许的
case(
    "int_to_real_ok",
    """
FUNCTION_BLOCK FB
VAR_INPUT n : INT; END_VAR
VAR_OUTPUT r : REAL; END_VAR
r := n * 2.5;
END_FUNCTION_BLOCK
""",
    True,
    "整数参与实数运算自动提升",
)

# ------------------------------------------------------- 12. MOD / 整数除法语义
case(
    "mod_div",
    """
FUNCTION_BLOCK FB
VAR_INPUT a : INT; b : INT; END_VAR
VAR_OUTPUT q : INT; m : INT; END_VAR
q := a / b;
m := a MOD b;
END_FUNCTION_BLOCK
""",
    True,
    "整除与取模",
)

# ----------------------------------------------------------------- 13. 实数除法
case(
    "real_div",
    """
FUNCTION_BLOCK FB
VAR_INPUT a : REAL; b : REAL; END_VAR
VAR_OUTPUT q : REAL; END_VAR
q := a / b;
END_FUNCTION_BLOCK
""",
    True,
    "实数除法",
)

# --------------------------------------------------- 14. CASE 与枚举/范围标签
case(
    "case_range",
    """
FUNCTION_BLOCK FB
VAR_INPUT n : INT; END_VAR
VAR_OUTPUT k : INT; END_VAR
CASE n OF
    1, 2: k := 10;
    3..5: k := 20;
ELSE
    k := 0;
END_CASE;
END_FUNCTION_BLOCK
""",
    True,
    "CASE 标签含范围",
)

# --------------------------------------------------------------- 15. FOR 循环
case(
    "for_loop",
    """
FUNCTION_BLOCK FB
VAR_INPUT n : INT; END_VAR
VAR_OUTPUT s : INT; END_VAR
VAR i : INT; END_VAR
s := 0;
FOR i := 1 TO n DO
    s := s + i;
END_FOR;
END_FUNCTION_BLOCK
""",
    True,
    "累加 1..n",
)


def run() -> int:
    failures = []
    for name, src, should_pass, why in CASES:
        res = check_st(src)
        ok = res.ok == should_pass
        mark = "PASS" if ok else "FAIL"
        print(f"[{mark}] {name:<24} 期望{'通过' if should_pass else '拦截'}  ({why})")
        if not ok:
            failures.append(name)
            for d in res.diags:
                print("        ", d)
    print(f"\n{len(CASES) - len(failures)}/{len(CASES)} 通过")
    return 0 if not failures else 1


def test_static_checker() -> None:
    """pytest 入口。"""
    assert run() == 0


# --------------------------------------------------------------------------
# 仿真语义测试：这里验证的是"解释器算得对不对"，而不是"代码写得对不对"
# --------------------------------------------------------------------------

EDGE_SRC = """
FUNCTION_BLOCK EdgeDetect
VAR_INPUT start : BOOL; END_VAR
VAR_OUTPUT count : INT; END_VAR
VAR prev : BOOL := FALSE; END_VAR
IF start AND NOT prev THEN
    count := count + 1;
END_IF;
prev := start;
END_FUNCTION_BLOCK
"""


def test_edge_detection() -> None:
    """上升沿计数：连续 3 个周期给 TRUE，只应加 1。"""
    outcome = simulate(
        EDGE_SRC,
        inputs=["start"],
        outputs=["count"],
        vectors=[
            {"start": True, "_expect": {"count": 1}},
            {"start": True, "_expect": {"count": 1}},
            {"start": True, "_expect": {"count": 1}},
        ],
    )
    assert outcome.ok, outcome.message


def test_int_division_truncates_toward_zero() -> None:
    """IEC 的 -7/2 必须是 -3（向零截断），Python 默认的 // 会给 -4。"""
    src = """
FUNCTION_BLOCK FB
VAR_INPUT a : INT; b : INT; END_VAR
VAR_OUTPUT q : INT; m : INT; END_VAR
q := a / b;
m := a MOD b;
END_FUNCTION_BLOCK
"""
    outcome = simulate(
        src,
        inputs=["a", "b"],
        outputs=["q", "m"],
        vectors=[{"a": -7, "b": 2, "_expect": {"q": -3, "m": -1}}],
    )
    assert outcome.ok, outcome.message


def test_output_holds_between_cycles() -> None:
    """VAR_OUTPUT 未被赋值时应保持上一周期的值，而不是清零。"""
    src = """
FUNCTION_BLOCK FB
VAR_INPUT set : BOOL; END_VAR
VAR_OUTPUT flag : BOOL; END_VAR
IF set THEN
    flag := TRUE;
END_IF;
END_FUNCTION_BLOCK
"""
    outcome = simulate(
        src,
        inputs=["set"],
        outputs=["flag"],
        vectors=[
            {"set": True, "_expect": {"flag": True}},
            {"set": False, "_expect": {"flag": True}},
        ],
    )
    assert outcome.ok, outcome.message


def test_array_lower_bound_respected() -> None:
    """ARRAY[1..5] 的下界是 1，越界要报运行期错误。"""
    src = """
FUNCTION_BLOCK FB
VAR_INPUT arr : ARRAY[1..5] OF INT; END_VAR
VAR_OUTPUT s : INT; END_VAR
VAR i : INT; END_VAR
s := 0;
FOR i := 1 TO 5 DO
    s := s + arr[i];
END_FOR;
END_FUNCTION_BLOCK
"""
    from stbench.st.interp import ArrayValue

    outcome = simulate(
        src,
        inputs=["arr"],
        outputs=["s"],
        vectors=[{"arr": ArrayValue(1, 5, [1, 2, 3, 4, 5]), "_expect": {"s": 15}}],
    )
    assert outcome.ok, outcome.message


def test_infinite_loop_guarded() -> None:
    """死循环必须被预算拦住，不能把实验卡死。"""
    src = """
FUNCTION_BLOCK FB
VAR_INPUT go : BOOL; END_VAR
VAR_OUTPUT x : INT; END_VAR
WHILE TRUE DO
    x := x + 1;
END_WHILE;
END_FUNCTION_BLOCK
"""
    outcome = simulate(src, inputs=["go"], outputs=["x"], vectors=[{"go": True}])
    assert not outcome.ok
    assert "超时" in outcome.message or "上限" in outcome.message


if __name__ == "__main__":
    code = run()
    print("\n--- 仿真语义 ---")
    for fn in (
        test_edge_detection,
        test_int_division_truncates_toward_zero,
        test_output_holds_between_cycles,
        test_array_lower_bound_respected,
        test_infinite_loop_guarded,
    ):
        try:
            fn()
            print(f"[PASS] {fn.__name__}")
        except AssertionError as e:
            code = 1
            print(f"[FAIL] {fn.__name__}: {e}")
    sys.exit(code)
