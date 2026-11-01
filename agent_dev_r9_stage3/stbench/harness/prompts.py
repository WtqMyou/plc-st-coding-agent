"""提示词构造。

**实验可复现性的一大半在这里**。提示词改了，历史数据就不能和新的比——
所以提示词全部集中在同一个文件、有版本号、写进实验记录的元数据里，
而不是散落在 runner 里用 f-string 拼。

三条经验（都来自踩坑，不是理论）：
1. **把接口表逐字抄进提示词**，别让模型"按需求自己设计接口"。接口名差一个
   大小写在 IEC 里无所谓（大小写不敏感），但少一个变量、或把 VAR_IN_OUT
   写成 VAR_INPUT，就是零分——这不是能力问题，是信息没给全。
2. **明确禁止用未在接口表出现的变量**。模型很喜欢顺手引入 ``timer``、
   ``prevValue`` 这类"聪明的"中间变量，然后忘了声明。
3. **修复轮只给"失败了什么"，不给答案**。把期望值直接贴出来等于泄题，
   模型会写死 ``IF count = 3 THEN avgOut := 4.0`` 这种考试作弊式代码。
"""

from __future__ import annotations

from ..schema import Problem

PROMPT_VERSION = "v2.5-task-specific-reset"

SYSTEM_PROMPT = """你是一名精通 IEC 61131-3 结构化文本（ST）的 PLC 工程师，正在为工业自动化控制场景编写功能块。

硬性要求：
1. 只输出**一个** ```st 代码块，代码块外不要写任何解释。
2. 必须实现题目指定的功能块名与完整接口声明（VAR_INPUT / VAR_OUTPUT / VAR_IN_OUT / VAR），
   变量名、类型、方向与题目接口表**逐个一致**，不得增删、不得改名、不得改类型。
3. 所有中间变量必须在 VAR 区显式声明；不得使用未声明的变量。
4. VAR_INPUT 在功能块内部只读，需要写入的形参必须用 VAR_IN_OUT。
5. 代码要能在真实 PLC 上编译：每个 IF / FOR / CASE / WHILE 都要正确闭合，
   END_FUNCTION_BLOCK 结尾。
6. 不要用注释掉的代码"占位"，不要留 TODO。
7. 目标为 CODESYS 3.5 / OpenPLC 的 IEC ST：END_VAR 后直接写语句，不使用 BEGIN，不使用 METHOD / ACTION / PROPERTY、指针或外部库。
8. 返回简洁的完整实现；不附测试程序或重复实现。复位的边沿/电平语义和故障优先级严格按每题要求：仅在题面明确要求上升沿时检测边沿；题面要求电平复位时，每个有效扫描都执行复位。不要将某一题的复位约定套用到其它题。"""


def _fmt_dir(v) -> str:
    """Direction 是枚举；直接 f-string 会打印成 ``Direction.INPUT``。"""
    d = v.direction
    return getattr(d, "value", str(d)).upper()


def build_task_prompt(problem: Problem, *, include_ltl: bool = True, platform_notes: str = "") -> str:
    """把一道题渲染成给模型的完整任务描述。"""
    lines: list[str] = []
    lines.append(f"# 任务：{problem.title}")
    lines.append("")
    lines.append("## 需求")
    lines.append(problem.requirements.strip())
    lines.append("")

    lines.append("## 接口定义（必须逐字实现，不得改动）")
    lines.append("")
    # target_pou 存的是 POU 种类（FUNCTION_BLOCK / FUNCTION / PROGRAM），
    # 题目里没有单独给实例名，统一用 FB —— 与参考解和测试用例的约定一致。
    lines.append("功能块名：`FB`（FUNCTION_BLOCK FB）")
    lines.append("")
    lines.append("| 变量名 | 类型 | 方向 | 说明 |")
    lines.append("| --- | --- | --- | --- |")
    for v in problem.variables:
        lines.append(f"| {v.name} | {v.data_type} | {_fmt_dir(v)} | {v.description} |")
        for f in v.fields:
            lines.append(f"| {v.name}.{f.name} | {f.data_type} | 结构体字段 | {f.description} |")
    lines.append("")

    if include_ltl and problem.specs:
        lines.append("## 必须满足的形式化性质")
        if problem.provenance.get('r9_spec_policy',{}).get('observer'):
            lines.append('以 __spec_ 开头的量是验证器从公开输入历史计算的观察量，无须在功能块中声明或引用；只实现接口与自然语言需求。')
        for s in problem.specs:
            lines.append(f"- [{s.sid}] {s.text}")
            if s.ltl:
                lines.append(f"  LTL: `{s.ltl}`")
        lines.append("")

    lines.append("## 补充说明")
    lines.append("- 功能块在**每个扫描周期**被调用一次，输出在周期结束时被采样。")
    lines.append("- 不要假设任何隐藏的定时器或全局变量；需要跨周期记住的状态请用 VAR 区静态变量。")
    lines.append("")
    lines.append("请直接给出完整的 ```st 代码块。")
    if platform_notes:
        lines.append("平台约定：" + platform_notes)
    return "\n".join(lines)


def build_fix_prompt(problem: Problem, previous_code: str, feedback: str, attempt: int) -> str:
    """把一次失败转成下一轮的修复指令。

    ``feedback`` 由 runner 从 StageResult 里提炼：只含**哪里错了**，
    绝不含"正确答案应该是什么"。
    """
    lines = [
        f"上一版代码未通过验证（第 {attempt} 次修正）。下面是具体的失败信息。",
        "",
        "## 你上一版提交的代码",
        "```st",
        previous_code.strip(),
        "```",
        "",
        "## 验证器反馈",
        feedback.strip(),
        "",
        "## 修正要求",
        "1. 只修改与反馈直接相关的地方，其余代码保持可用。",
        "2. 不要为了让某个测试用例通过而硬编码具体数值（如 `IF count = 3 THEN out := 4.0`）。",
        "3. 如果反馈说明变量未声明，就在 VAR 区补上声明，而不是改接口。",
        "4. 重新输出**完整**的 ```st 代码块（不要只给 diff 片段）。",
    ]
    return "\n".join(lines)


def build_system_prompt() -> str:
    return SYSTEM_PROMPT
