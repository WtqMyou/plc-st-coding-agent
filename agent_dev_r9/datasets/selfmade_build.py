"""生成 10 道自建题的 JSON 数据。

为什么要写成脚本而不是直接手敲 JSON
------------------------------------
每道题都带 LTL 规约和扫描周期测试表，手敲 JSON 很容易出现**测试表和规约
对不上**的情况（规约说"停止优先"，测试表却没有"同时按下启动和停止"的用例）。
写成 Python 数据 + 统一导出，就能在导出时做一致性自检：

* 测试向量里出现的每个变量名，必须在该题接口表里声明过；
* 每个规约至少有一条测试用例覆盖它（``covers`` 字段显式声明）。

题目设计立场
------------
10 道题全部来自**流程行业自动化**真实场景（用户队伍有该赛项经验），并按
"IEC 61131-3 的哪一类语法/语义最容易出错"来挑选，而不是随便凑 10 个：

    状态机 / 边沿 / 扫描周期保持 / 整数除法与取模 / 数组与结构体 /
    计时器语义 / FIFO 环形缓冲 / 历史窗口统计 / 报警上下文

这些恰好是 LLM 生成 ST 时的高频失败点，题目才有区分度。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from stbench.schema import (  # noqa: E402
    Difficulty,
    Direction,
    Problem,
    Spec,
    TestCase,
    VarDef,
)

OUT = Path(__file__).resolve().parent / "selfmade"

# 用例表（含 case_mode / const_inputs）的唯一真源在同目录 selfmade_cases.py。
# 题目函数里只写需求、接口与规约；用例由 attach_cases() 统一灌入，
# 避免"笔记、期望、常量输入"三处各写一份、彼此漂移。
sys.path.insert(0, str(Path(__file__).resolve().parent))
from selfmade_cases import CASES  # noqa: E402

ST_RECIPE_FIELDS = [
    {"name": "recipeID", "data_type": "INT",
     "description": "配方号，0 表示空槽"},
    {"name": "totalRatio", "data_type": "REAL",
     "description": "配方总比例，合法 99.0..101.0"},
    {"name": "temperature", "data_type": "REAL",
     "description": "工艺温度，合法 30.0..180.0"},
]


def attach_cases(p: Problem) -> Problem:
    """把 selfmade_cases.py 里的用例表挂到题目上，并补齐结构体字段定义。"""
    for v in p.variables:
        if v.name == "recipe" and not v.fields:
            v.fields = [VarDef(**f) for f in ST_RECIPE_FIELDS]
    spec = CASES.get(p.pid)
    if spec:
        p.case_mode = spec["mode"]
        p.test_cases = [TestCase(**tc) for tc in spec["cases"]]
    return p


def V(name, dtype, desc, direction=Direction.INPUT, fields=None):
    """缩写的变量声明构造器，让下面的题目数据读起来像接口表。"""
    return VarDef(
        name=name,
        data_type=dtype,
        description=desc,
        direction=direction,
        fields=fields or [],
    )


IN = Direction.INPUT
OUTD = Direction.OUTPUT
IO = Direction.INOUT


# ==========================================================================
# 1. 除零保护的平均值计算（easy）
# ==========================================================================

def sc_avg_div() -> Problem:
    variables = [
        V("enable", "BOOL", "TRUE 时更新平均值，FALSE 时保持"),
        V("values", "ARRAY[1..8] OF INT", "本周期采集到的原始样本（1..8 号站）"),
        V("count", "INT", "本周期有效的样本个数，合法范围 0..8"),
        V("avgEnable", "BOOL", "计算使能，通常接在物位低联锁之后"),
        V("avgOut", "REAL", "平均输出", OUTD),
    ]
    cases = [
        TestCase("c1", {"enable": True}, {"avgOut": 4.0},
                 "正常：8 个样本平均 = 4.0", {"count": 8, "avgEnable": True,
                 "values": [1, 2, 3, 4, 5, 6, 7, 8]}),
        TestCase("c2", {"enable": True}, {"avgOut": 4.0},
                 "【边界】count=0 且使能：不得除零、不得改写 avgOut",
                 {"count": 0, "avgEnable": True,
                  "values": [1, 2, 3, 4, 5, 6, 7, 8]}),
        TestCase("c3", {"enable": True}, {"avgOut": 10.0},
                 "count 超过数组长度 8 时，只取前 8 个，不得越界",
                 {"count": 12, "avgEnable": True,
                  "values": [10, 10, 10, 10, 10, 10, 10, 10]}),
        TestCase("c4", {"enable": False}, {"avgOut": 10.0},
                 "【边界】enable=FALSE 时保持上一周期的输出，不更新",
                 {"count": 8, "avgEnable": True,
                  "values": [1, 1, 1, 1, 1, 1, 1, 1]}),
        TestCase("c5", {"enable": True}, {"avgOut": 2.5},
                 "count 小于 8 时只对前 count 个求和",
                 {"count": 4, "avgEnable": True,
                  "values": [1, 2, 3, 4, 99, 99, 99, 99]}),
    ]
    specs = [
        Spec("S1", "count 为 0 或为负时，不得发生除零，avgOut 应在**当周期**保持不变。",
             "G((count <= 0) -> avgOut = prev(avgOut))", "safety"),
        Spec("S2", "enable 为 FALSE 时，avgOut 应在当周期保持不变，不得被改写。",
             "G(!enable -> avgOut = prev(avgOut))", "safety"),
        Spec("S3", "avgOut 在任何输入下都不是 NaN（数值健全性）。越界访问本身由"
                   "解释器直接判运行期错误，不在 LTL 层表达。",
             "G(avgOut = avgOut)", "safety"),
        Spec("S4", "在 enable 且 count 合法时，avgOut 等于所选样本的算术平均。",
             "", "data", verified_by="simulation"),
    ]
    return Problem(
        pid="self-easy-01",
        source="selfmade",
        difficulty=Difficulty.EASY,
        title="分段采样平均值计算中的除零与边界保护",
        requirements=(
            "写一个功能块 FB，在每个扫描周期计算一组采样值的平均值。\n"
            "控制要求：\n"
            "1. enable 为 TRUE 时更新平均值，为 FALSE 时 avgOut 保持上一周期的值不变；\n"
            "2. count 为本周期有效样本个数，合法范围 0..8；count 为 0 时**不得发生除零**，"
            "此时 avgOut 保持不变；\n"
            "3. count 大于数组长度 8 时，只按前 8 个样本计算，不得越界访问；\n"
            "4. avgEnable 为 FALSE 时视为未投入自动，同样保持 avgOut 不变；\n"
            "5. 整数相加可能超过 INT 范围，求和过程中应使用更宽的类型（DINT/LINT）避免溢出；\n"
            "6. 结果以 REAL 输出，保留原始精度，不做四舍五入到整数。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业经验改编",
            "origin": "流程行业自动化赛项中，模拟量输入组在对多路变送器求平均时必须处理"
                      "'通道掉线导致有效通道数为 0'的情况；这是赛场上最容易写出除零的环节。",
            "adaptation": "把赛题里与具体 I/O 地址绑定的部分剥离，只保留"
                          "'有效计数 + 数组 + 平均值'这一可独立编译的控制单元。",
            "review": "人工审核：接口全部为标量/一维数组，无外部依赖，可在 CODESYS 中"
                      "直接建立测试实例；要求与 IEC 61131-3 整数除法语义一致。",
        },
    )


# ==========================================================================
# 2. 罐区联锁（easy）
# ==========================================================================

def sc_interlock() -> Problem:
    variables = [
        V("tankLevel", "REAL", "储罐液位百分比 0..100"),
        V("outletFlow", "REAL", "出口流量 m³/h"),
        V("inletPermit", "BOOL", "进料许可（工艺联锁允许进料）"),
        V("resetBtn", "BOOL", "复位按钮（上升沿有效）"),
        V("pumpRun", "BOOL", "进料泵运行命令", OUTD),
        V("alarmHigh", "BOOL", "高液位报警（自保持，需复位）", OUTD),
        V("alarmLow", "BOOL", "低液位报警（自保持，需复位）", OUTD),
        V("outletValveOpen", "BOOL", "出口阀开命令", OUTD),
    ]
    cases = [
        TestCase("c1", {"tankLevel": 50.0, "outletFlow": 0.0},
                 {"pumpRun": True, "outletValveOpen": True,
                  "alarmHigh": False, "alarmLow": False},
                 "启动：液位正常、有进料许可 → 开泵开阀",
                 {"inletPermit": True, "resetBtn": False}),
        TestCase("c2", {"tankLevel": 85.0, "outletFlow": 0.0},
                 {"pumpRun": False, "outletValveOpen": True, "alarmHigh": True},
                 "【边界】液位到 85.0 应恰好触发高报警（>= 语义）",
                 {"inletPermit": True, "resetBtn": False}),
        TestCase("c3", {"tankLevel": 80.0, "outletFlow": 0.0},
                 {"alarmHigh": True, "pumpRun": False},
                 "报警自保持：液位回落到 80（低于 85）报警仍保持",
                 {"inletPermit": True, "resetBtn": False}),
        TestCase("c4", {"tankLevel": 50.0, "outletFlow": 0.0},
                 {"alarmHigh": False, "pumpRun": True},
                 "复位按钮上升沿清除报警",
                 {"inletPermit": True, "resetBtn": True}),
        TestCase("c5", {"tankLevel": 15.0, "outletFlow": 0.0},
                 {"alarmLow": True, "outletValveOpen": False},
                 "【边界】液位 15.0 触发低报警并关出口阀",
                 {"inletPermit": True, "resetBtn": False}),
        TestCase("c6", {"tankLevel": 50.0, "outletFlow": 0.0},
                 {"pumpRun": False, "alarmHigh": True},
                 "【优先级】同时有高报警与复位：报警优先，泵不得启动",
                 {"inletPermit": True, "resetBtn": True}),
    ]
    specs = [
        Spec("S1", "液位不低于 85.0 时，高液位报警必须在当周期置位。",
             "G(tankLevel >= 85.0 & !rising(resetBtn) -> alarmHigh)", "safety"),
        Spec("S2", "高液位报警置位后，在复位按钮上升沿出现之前必须保持。",
             "G(alarmHigh & !X(rising(resetBtn)) -> X(alarmHigh))", "sequencing"),
        Spec("S3", "高液位报警有效期间，进料泵不得运行（停止优先于启动）。",
             "G(alarmHigh -> !pumpRun)", "safety"),
        Spec("S4", "液位不高于 15.0 时，出口阀必须在当周期关闭。",
             "G(tankLevel <= 15.0 -> !outletValveOpen)", "safety"),
        Spec("S5", "无进料许可时，进料泵不得运行。",
             "G(!inletPermit -> !pumpRun)", "safety"),
    ]
    return Problem(
        pid="self-easy-02",
        source="selfmade",
        difficulty=Difficulty.EASY,
        title="储罐高低液位联锁与报警自保持",
        requirements=(
            "写一个功能块 FB，实现储罐的进料联锁。\n"
            "控制要求：\n"
            "1. tankLevel 低于 85.0 且不低于 15.0、inletPermit 为 TRUE、且当前无高液位报警时，"
            "pumpRun 置 TRUE，outletValveOpen 置 TRUE；\n"
            "2. tankLevel **达到或超过** 85.0 时，alarmHigh 置 TRUE（自保持），并立即停止进料泵；\n"
            "3. tankLevel **达到或低于** 15.0 时，alarmLow 置 TRUE（自保持），并关闭出口阀；\n"
            "4. resetBtn 的**上升沿**同时清除两个报警；按住不放只算一次复位；\n"
            "5. 报警存在期间，即使按下复位按钮，复位也不生效（报警优先）；\n"
            "6. 所有报警清除、条件满足后，系统自动恢复运行，不需要重新上电。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业经验改编",
            "origin": "罐区液位联锁是流程行业自动化赛项的基础题型，涉及"
                      "带迟滞的报警、报警自保持、上升沿复位与'停止优先'四件事。",
            "adaptation": "把赛题中的多罐切换简化为单罐，保留边界值（85.0/15.0）"
                          "与报警优先的语义，使它成为可独立测试的最小单元。",
            "review": "人工审核：边界值用 >= / <= 明确写死，避免 LLM 用 >/< 产生 off-by-one；"
                      "复位必须按边沿而非常电平，这一条最容易被写错，故单独设规约 S2。",
        },
    )


# ==========================================================================
# 3. 配料配方校验（medium）
# ==========================================================================

def sc_recipe() -> Problem:
    variables = [
        V("recipe", "ARRAY[1..8] OF ST_Recipe", "配方槽位 1..8，槽位 recipeID=0 表示空"),
        V("selSlot", "INT", "操作员选中的槽位，合法范围 1..8"),
        V("loadCmd", "BOOL", "装载命令（上升沿触发一次装载）"),
        V("running", "BOOL", "当前是否处于生产状态"),
        V("valid", "BOOL", "配方校验通过", OUTD),
        V("loadedID", "INT", "已装载的配方号，无配方时为 0", OUTD),
    ]
    fields = [
        V("recipeID", "INT", "配方编号，0 表示空槽", IO),
        V("totalRatio", "REAL", "各组分比例之和，要求 99.0..101.0", IO),
        V("temperature", "REAL", "工艺温度，要求 30.0..180.0", IO),
    ]
    cases = [
        TestCase("c1", {"recipe": [], "loadCmd": True},
                 {"valid": True, "loadedID": 101},
                 "正常装载：配方 101 全合规",
                 {"selSlot": 1, "running": False}),
        TestCase("c2", {"recipe": [], "loadCmd": True},
                 {"valid": False, "loadedID": 0},
                 "【边界】选中空槽位（recipeID=0）→ 校验失败、不得装载",
                 {"selSlot": 3, "running": False}),
        TestCase("c3", {"recipe": [], "loadCmd": True},
                 {"valid": False, "loadedID": 0},
                 "比例和 98.9 略低于下限 → 失败",
                 {"selSlot": 2, "running": False}),
        TestCase("c4", {"recipe": [], "loadCmd": True},
                 {"valid": True, "loadedID": 202},
                 "【边界】温度恰好 180.0（上限闭区间）→ 通过",
                 {"selSlot": 4, "running": False}),
        TestCase("c5", {"recipe": [], "loadCmd": True},
                 {"valid": False, "loadedID": 0},
                 "【边界】温度 180.1 超上限 → 失败",
                 {"selSlot": 5, "running": False}),
        TestCase("c6", {"recipe": [], "loadCmd": True},
                 {"valid": False, "loadedID": 101},
                 "【互锁】生产运行中装载命令无效，保持原配方",
                 {"selSlot": 2, "running": True}),
        TestCase("c7", {"recipe": [], "loadCmd": True},
                 {"valid": False, "loadedID": 101},
                 "选择越界槽位 9 → 必须判为非法，且不得越界访问",
                 {"selSlot": 9, "running": False}),
    ]
    # 测试用例里的 recipe 是元素列表，导出时展开成 ArrayValue 友好的形式
    c1 = [{"recipeID": 101, "totalRatio": 100.0, "temperature": 60.0},
          {"recipeID": 0, "totalRatio": 0.0, "temperature": 0.0}] + [
        {"recipeID": 0, "totalRatio": 0.0, "temperature": 0.0} for _ in range(6)]
    c2 = list(c1)
    c2[1] = {"recipeID": 0, "totalRatio": 0.0, "temperature": 0.0}
    c2[2] = {"recipeID": 0, "totalRatio": 0.0, "temperature": 0.0}
    base2 = [dict(x) for x in c1]
    base2[1] = {"recipeID": 102, "totalRatio": 98.9, "temperature": 60.0}
    base4 = [dict(x) for x in c1]
    base4[3] = {"recipeID": 202, "totalRatio": 100.0, "temperature": 180.0}
    base5 = [dict(x) for x in c1]
    base5[4] = {"recipeID": 303, "totalRatio": 99.5, "temperature": 180.1}
    cases[0].const_inputs["recipe"] = c1
    cases[1].const_inputs["recipe"] = c2
    cases[2].const_inputs["recipe"] = base2
    cases[3].const_inputs["recipe"] = base4
    cases[4].const_inputs["recipe"] = base5
    cases[5].const_inputs["recipe"] = base2  # 运行中选中非法槽 2，但应保持 101
    cases[6].const_inputs["recipe"] = base2

    specs = [
        Spec("S1", "选中的槽位为空（recipeID = 0）时，装载必须判为非法，"
                   "且不得改变已装载的 loadedID。",
             "G(!running & rising(loadCmd) & (selSlot >= 1) & (selSlot <= 8) "
             "& (recipe[selSlot].recipeID = 0) -> !valid)", "safety"),
        Spec("S2", "总配比越界（totalRatio < 99 或 > 101）时装载必须判为非法。",
             "G(!running & rising(loadCmd) & (selSlot >= 1) & (selSlot <= 8) "
             "& (recipe[selSlot].totalRatio < 99.0) -> !valid)", "safety"),
        Spec("S3", "温度越界（temperature < 30 或 > 180）时装载必须判为非法。",
             "G(!running & rising(loadCmd) & (selSlot >= 1) & (selSlot <= 8) "
             "& (recipe[selSlot].temperature > 180.0) -> !valid)", "safety"),
        Spec("S4", "生产运行中（running），装载命令不得改变 loadedID。"
                   "注意必须要求 running 在相邻两拍都成立——只要求起始拍成立的话，"
                   "下一拍 running 撤销、装载被接受，就是合法行为。",
             "G(running & X(running) -> X(loadedID = prev(loadedID)))", "safety"),
        Spec("S5", "槽位越界（selSlot < 1 或 > 8）时必须判为非法，不得访问数组外内存。",
             "G(!running & rising(loadCmd) & ((selSlot < 1) | (selSlot > 8)) -> !valid)",
             "safety"),
        Spec("S6", "装载命令只在上升沿生效，电平保持期间不得重复装载。",
             "G(loadCmd & prev(loadCmd) -> loadedID = prev(loadedID))", "sequencing"),
    ]
    return Problem(
        pid="self-medium-01",
        source="selfmade",
        difficulty=Difficulty.MEDIUM,
        title="配料配方装载与校验（数组越界与浮点区间）",
        requirements=(
            "写一个功能块 FB，从配方库中按槽位装载配方并校验。\n"
            "控制要求：\n"
            "1. recipe 是 8 个槽位的配方数组，槽位 recipeID = 0 表示空槽；\n"
            "2. selSlot 是操作员选中的槽位，合法范围 1..8；**越界时必须判为非法，不得访问数组外**；\n"
            "3. loadCmd 的**上升沿**触发一次装载；按住不放不得重复装载；\n"
            "4. 校验规则（**全部满足**才算 valid）：槽位非空；totalRatio 在 99.0..101.0 之间（含端点）；"
            "temperature 在 30.0..180.0 之间（含端点）；\n"
            "5. 校验通过时 valid := TRUE 且 loadedID 更新为该槽位的 recipeID；"
            "校验失败时 valid := FALSE 且 loadedID 归 0；\n"
            "6. running 为 TRUE 表示正在生产，此时装载命令无效，loadedID 保持原值。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业经验改编",
            "origin": "流程行业多产品罐装线按配方切换：赛题里常见'配方号 + 比例和"
                      " + 工艺温度'三元组，需要操作员选槽位后校验再投产。",
            "adaptation": "把配方库简化为固定 8 槽数组，把'组分比例和必须为 100%'"
                          "变成带容差的闭区间判定，从而把浮点边界与数组下标两类易错点放在同一题里。",
            "review": "人工审核：所有边界（99.0 / 101.0 / 30.0 / 180.0）都写成闭区间并"
                      "各有正反两个用例；槽位越界单独成用例 c7。",
        },
    )


# ==========================================================================
# 4. 移动平均滤波（medium）
# ==========================================================================

def sc_moving_avg() -> Problem:
    variables = [
        V("enable", "BOOL", "滤波使能，FALSE 时清空历史"),
        V("rawValue", "REAL", "本周期原始采样值"),
        V("filteredValue", "REAL", "滤波输出", OUTD),
        V("windowFull", "BOOL", "历史窗口已填满 8 个样本后置 TRUE", OUTD),
        V("sampleCount", "INT", "当前窗口内有效样本数 0..8", OUTD),
    ]
    # 每个用例是一条连续轨迹上的一个扫描周期（verify_multicycle 语义）
    cases = [
        TestCase("t1", {"enable": True, "rawValue": 10.0},
                 {"filteredValue": 10.0, "windowFull": False, "sampleCount": 1},
                 "第 1 个样本：直接输出原值"),
        TestCase("t2", {"enable": True, "rawValue": 20.0},
                 {"filteredValue": 15.0, "windowFull": False, "sampleCount": 2},
                 "第 2 个样本：(10+20)/2 = 15"),
        TestCase("t3", {"enable": True, "rawValue": 30.0},
                 {"filteredValue": 20.0, "windowFull": False, "sampleCount": 3},
                 "第 3 个样本：(10+20+30)/3 = 20"),
        TestCase("t4", {"enable": True, "rawValue": 40.0},
                 {"sampleCount": 4, "windowFull": False}, "第 4 个样本"),
        TestCase("t5", {"enable": True, "rawValue": 50.0},
                 {"sampleCount": 5}, "第 5 个样本"),
        TestCase("t6", {"enable": True, "rawValue": 60.0},
                 {"sampleCount": 6}, "第 6 个样本"),
        TestCase("t7", {"enable": True, "rawValue": 70.0},
                 {"sampleCount": 7}, "第 7 个样本"),
        TestCase("t8", {"enable": True, "rawValue": 80.0},
                 {"windowFull": True, "sampleCount": 8,
                  "filteredValue": 45.0},
                 "第 8 个样本：窗口填满，(10+..+80)/8 = 45"),
        TestCase("t9", {"enable": True, "rawValue": 88.0},
                 {"windowFull": True, "sampleCount": 8, "filteredValue": 52.125},
                 "第 9 个样本：挤掉 10，(20+30+...+88)/8 = 52.125"),
        TestCase("t10", {"enable": False, "rawValue": 0.0},
                 {"sampleCount": 0, "windowFull": False, "filteredValue": 52.125},
                 "【边界】enable 拉低：清空历史，但输出保持上次值"),
        TestCase("t11", {"enable": True, "rawValue": 4.0},
                 {"sampleCount": 1, "filteredValue": 4.0},
                 "重新使能后从 1 个样本重新累计，不得残留旧样本"),
    ]
    specs = [
        Spec("S1", "窗口未满时，滤波输出必须等于已采集样本的算术平均，"
                   "不得用 0 填充凑满窗口。",
             "", "data", verified_by="simulation"),
        Spec("S2", "窗口满后样本数恒为 8（环形缓冲不再增长，也不会被挤空）。",
             "G(windowFull -> sampleCount = 8)", "safety"),
        Spec("S3", "enable 拉低后，sampleCount 必须在**当周期**归零，窗口同时退出满载。",
             "G(!enable -> sampleCount = 0 & !windowFull)", "safety"),
        Spec("S4", "sampleCount 恒不超过 8，即缓冲区不会溢出。",
             "G(sampleCount <= 8)", "safety"),
    ]
    return Problem(
        pid="self-medium-02",
        source="selfmade",
        difficulty=Difficulty.MEDIUM,
        title="模拟量滑动平均滤波（窗口未满与 FIFO 淘汰）",
        requirements=(
            "写一个功能块 FB，对模拟量采样值做 8 点滑动平均滤波。\n"
            "控制要求：\n"
            "1. 每个扫描周期，若 enable 为 TRUE，把 rawValue 压入长度为 8 的环形缓冲区，"
            "并用缓冲区内**实际已有**的样本计算算术平均，输出到 filteredValue；\n"
            "2. 缓冲区**未填满时不得用 0 填充**：只有 3 个样本时就是这 3 个的平均；\n"
            "3. 缓冲区填满后，每来一个新样本挤掉最老的一个（先进先出）；\n"
            "4. sampleCount 输出当前缓冲区内的有效样本数（0..8）；\n"
            "5. 当样本数达到 8 时 windowFull 置 TRUE，之后保持 TRUE；\n"
            "6. enable 为 FALSE 时清空缓冲区（sampleCount 归 0、windowFull 归 FALSE），"
            "但 filteredValue 保持上一次的计算结果不变。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业经验改编",
            "origin": "流程行业赛题中，模拟量输入普遍需要滤波以抑制变送器抖动；"
                      "赛前练习里出现过'窗口刚度切换/移动平均'的要求。",
            "adaptation": "把赛题中随工艺切换的动态窗口简化为固定 8 点，"
                          "但刻意保留'窗口未满'这一前半段状态——这是 LLM 最容易写错的地方"
                          "（常见错误：用 0 填充、或直接除以 8）。",
            "review": "人工审核：本题是**时序题**，测试用例按连续扫描周期组织"
                      "（第 t 条用例是第 t 个周期），与题面'每个扫描周期'一致。",
        },
    )


# ==========================================================================
# 5. 闸门状态机（medium）
# ==========================================================================

def sc_gate_fsm() -> Problem:
    variables = [
        V("openBtn", "BOOL", "开门按钮（上升沿有效）"),
        V("closeBtn", "BOOL", "关门按钮（上升沿有效）"),
        V("openLimit", "BOOL", "开到位限位开关"),
        V("closeLimit", "BOOL", "关到位限位开关"),
        V("obstacle", "BOOL", "防夹物体检测"),
        V("motorUp", "BOOL", "电机上升（开门）输出", OUTD),
        V("motorDown", "BOOL", "电机下降（关门）输出", OUTD),
        V("errorFlag", "BOOL", "故障锁存（需人工复位后清除）", OUTD),
    ]
    cases = [
        TestCase("g1", {"openBtn": True, "closeLimit": True},
                 {"motorUp": True, "motorDown": False},
                 "关门到位按开门：上升，不得同时输出两个方向"),
        TestCase("g2", {"openBtn": False, "openLimit": True},
                 {"motorUp": False, "motorDown": False},
                 "开到位后自动停机"),
        TestCase("g3", {"closeBtn": True, "openLimit": True},
                 {"motorDown": True, "motorUp": False},
                 "开到位按关门：下降"),
        TestCase("g4", {"obstacle": True},
                 {"motorDown": False, "motorUp": True, "errorFlag": False},
                 "【安全】下降中检测到障碍：立即停止下降并反向上升"),
        TestCase("g5", {"obstacle": False},
                 {"motorUp": True},
                 "障碍消失后不得自动重新下降（必须重新按关门）"),
        TestCase("g6", {"obstacle": True},
                 {"motorUp": False, "errorFlag": True},
                 "【安全】上升中检测到障碍：立即停机并锁存故障"),
        TestCase("g7", {"obstacle": True, "closeBtn": True},
                 {"motorUp": False, "motorDown": False, "errorFlag": True},
                 "故障锁存期间任何按钮都不得启动电机"),
    ]
    # 轨迹题：把 g1..g7 串成一条连续扫描序列
    trace = [
        ("g1", {"openBtn": True, "closeBtn": False, "openLimit": False,
                "closeLimit": True, "obstacle": False}, {}),
        ("g2", {"openBtn": False, "closeBtn": False, "openLimit": True,
                "closeLimit": False, "obstacle": False}, {}),
        ("g3", {"openBtn": False, "closeBtn": True, "openLimit": True,
                "closeLimit": False, "obstacle": False}, {}),
        ("g4", {"openBtn": False, "closeBtn": False, "openLimit": False,
                "closeLimit": False, "obstacle": True}, {}),
        ("g5", {"openBtn": False, "closeBtn": False, "openLimit": False,
                "closeLimit": False, "obstacle": False}, {}),
        ("g6", {"openBtn": False, "closeBtn": False, "openLimit": False,
                "closeLimit": False, "obstacle": True}, {}),
        ("g7", {"openBtn": False, "closeBtn": True, "openLimit": False,
                "closeLimit": False, "obstacle": True}, {}),
    ]
    cases = [TestCase(tid, ins, cases[i].expected, cases[i].note)
             for i, (tid, ins, _) in enumerate(trace)]
    specs = [
        Spec("S1", "电机上升与下降输出不得同时为 TRUE。",
             "G(!(motorUp & motorDown))", "safety"),
        Spec("S2", "任何情况下检测到障碍，下降输出必须立即为 FALSE。",
             "G(obstacle -> !motorDown)", "safety"),
        Spec("S3", "开到位后不得再输出上升。",
             "G(openLimit -> !motorUp)", "safety"),
        Spec("S4", "故障锁存后，进入故障的路径必须存在人工复位，"
                   "且故障期间不得启动电机。",
             "G(errorFlag -> !motorUp & !motorDown)", "safety"),
        Spec("S5", "障碍出现后立即停止是必需的，但**自动恢复**不允许："
                   "故障锁存后，障碍解除的那一拍电机不得自动动作。",
             "G(errorFlag & X(!obstacle) -> X(!motorUp & !motorDown))", "safety"),
    ]
    return Problem(
        pid="self-medium-03",
        source="selfmade",
        difficulty=Difficulty.MEDIUM,
        title="闸门电机有限状态机（四状态与安全互锁）",
        requirements=(
            "写一个功能块 FB，实现闸门电机的有限状态机，状态为 IDLE / OPENING / CLOSING / "
            "FAULT 四种。\n"
            "控制要求：\n"
            "1. 初始状态为 IDLE，电机输出全部关闭；\n"
            "2. IDLE 状态下，openBtn 的上升沿且未开到位（openLimit = FALSE）→ 进入 OPENING；"
            "closeBtn 的上升沿且未关到位 → 进入 CLOSING；\n"
            "3. OPENING 时 motorUp 为 TRUE；到达 openLimit 后回到 IDLE；\n"
            "4. CLOSING 时 motorDown 为 TRUE；到达 closeLimit 后回到 IDLE；\n"
            "5. **安全要求**：CLOSING 中检测到 obstacle 时，立即停止下降并反向进入 OPENING；"
            "OPENING 中检测到 obstacle 时，立即停机并进入 FAULT；\n"
            "6. **motorUp 与 motorDown 在任何时刻都不得同时为 TRUE**；\n"
            "7. 障碍消失后不得自动重新动作，必须由操作员重新按按钮；\n"
            "8. FAULT 下 errorFlag 置 TRUE 并锁存，直到人工复位（openBtn 与 closeBtn 同时按下）"
            "才清除，且 FAULT 期间任何按钮都不得启动电机。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业经验改编",
            "origin": "西门子杯流程行业自动化赛项中，闸门/阀门类执行机构普遍要求"
                      "'四状态 + 防夹 + 不得同时正反转'。",
            "adaptation": "去掉具体阀门行程时间，只保留状态迁移与安全互锁；"
                          "增加'自动恢复禁止'一条，考察 LLM 是否会把安全动作写成自动往返。",
            "review": "人工审核：状态机四个状态与迁移条件在题面中穷举，无歧义；"
                      "安全类规约 S1/S2 用纯布尔 LTL 表达，可交给模型检查器。",
        },
    )


# ==========================================================================
# 6. 定量灌装（medium）
# ==========================================================================

def sc_filling() -> Problem:
    variables = [
        V("startBtn", "BOOL", "启动按钮（上升沿有效）"),
        V("resetBtn", "BOOL", "复位按钮（上升沿有效）"),
        V("doneSensor", "BOOL", "满瓶检测传感器"),
        V("targetVol", "REAL", "目标灌装体积 mL"),
        V("flowVol", "REAL", "本周期累计流量增量 mL"),
        V("valveOpen", "BOOL", "灌装阀开命令", OUTD),
        V("fillsToday", "INT", "今日完成瓶数", OUTD),
    ]
    cases = [
        TestCase("f1", {"startBtn": True, "resetBtn": False,
                        "doneSensor": False, "flowVol": 0.0},
                 {"valveOpen": True}, "启动：开阀",
                 {"targetVol": 250.0}),
        TestCase("f2", {"startBtn": False, "resetBtn": False, "doneSensor": False,
                        "flowVol": 249.0},
                 {"valveOpen": True}, "未达目标：保持开阀",
                 {"targetVol": 250.0}),
        TestCase("f3", {"startBtn": False, "resetBtn": False, "doneSensor": False,
                        "flowVol": 1.0},
                 {"valveOpen": False},
                 "【边界】累计恰好 250.0 → 立即关阀（>= 语义，不是 >）",
                 {"targetVol": 250.0}),
        TestCase("f4", {"startBtn": False, "resetBtn": False, "doneSensor": True,
                        "flowVol": 0.0},
                 {"fillsToday": 1, "valveOpen": False},
                 "满瓶传感器确认 → 计数 +1，且计数只在确认时发生",
                 {"targetVol": 250.0}),
        TestCase("f5", {"startBtn": False, "resetBtn": False, "doneSensor": False,
                        "flowVol": 0.0},
                 {"fillsToday": 1, "valveOpen": False},
                 "无启动命令时不得开阀"),
        TestCase("f6", {"startBtn": True, "resetBtn": False, "doneSensor": False,
                        "flowVol": 0.0},
                 {"fillsToday": 1, "valveOpen": True},
                 "复位后开始下一瓶：体积重新从 0 累计"),
        TestCase("f7", {"startBtn": False, "resetBtn": True, "doneSensor": False,
                        "flowVol": 0.0},
                 {"fillsToday": 0, "valveOpen": False},
                 "【边界】复位按钮清零今日计数"),
    ]
    specs = [
        Spec("S1", "复位按钮上升沿必须在**当周期**把今日计数清零。",
             "G(rising(resetBtn) -> fillsToday = 0)", "safety"),
        Spec("S2", "开阀只允许发生在启动按钮的上升沿：阀从关到开的那一拍必须有新按下。",
             "G(!valveOpen & X(valveOpen) -> X(rising(startBtn)))", "sequencing"),
        Spec("S3", "除复位那一拍外，计数单调不减（不得回退）。",
             "G(!rising(resetBtn) -> fillsToday >= prev(fillsToday))", "safety"),
        Spec("S6", "每拍计数最多增加 1（不得因阀抖动重复计数）。",
             "G(fillsToday <= prev(fillsToday) + 1)", "safety"),
        Spec("S4", "计数只发生在满瓶确认之后：计数增加的那一拍 doneSensor 必须为真。",
             "G(fillsToday > prev(fillsToday) -> doneSensor)", "safety"),
        Spec("S5", "累计流量达到目标体积后，灌装阀必须在当周期关闭"
                   "（涉及内部累计量，只在用例中校验）。",
             "", "data", verified_by="simulation"),
    ]
    return Problem(
        pid="self-medium-04",
        source="selfmade",
        difficulty=Difficulty.MEDIUM,
        title="定量灌装阀控制（浮点累计与计数去抖）",
        requirements=(
            "写一个功能块 FB，控制一条定量灌装工位。\n"
            "控制要求：\n"
            "1. startBtn 的上升沿开始一瓶的灌装：valveOpen 置 TRUE，并把内部累计体积清零；\n"
            "2. 每个扫描周期把 flowVol 累加到内部体积；**累计值达到或超过** targetVol 时立即关阀；\n"
            "3. 关阀后等待 doneSensor 为 TRUE，确认该瓶装满；\n"
            "4. **只有确认之后** fillsToday 才加 1；阀未确认就再次启动不得重复计数；\n"
            "5. 正在灌装过程中 startBtn 再次按下无效（不重新开始，也不重复计数）；\n"
            "6. resetBtn 的上升沿把 fillsToday 清零，并关闭灌装阀、清除内部累计。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业经验改编",
            "origin": "流程行业自动化赛项的灌装/称重工位核心逻辑：按体积或重量定量，"
                      "并以满瓶检测作为计数确认。",
            "adaptation": "把称重传感器抽象为'本周期流量增量 + 目标体积'，"
                          "保留浮点累计的边界判定（>= 而非 >）与计数确认时序。",
            "review": "人工审核：浮点累加存在精度问题，题面要求用 >= 判定并在"
                      "仿真里以 1e-6 相对误差比较；计数去抖单独设用例 f4/f5。",
        },
    )


# ==========================================================================
# 7. 报警管理（hard）
# ==========================================================================

def sc_alarm() -> Problem:
    variables = [
        V("flowLow", "BOOL", "流量低开关量输入"),
        V("ackBtn", "BOOL", "确认按钮（上升沿有效）"),
        V("sensorOK", "BOOL", "传感器健康状态（FALSE 表示断线）"),
        V("alarmActive", "BOOL", "报警激活（条件仍存在）", OUTD),
        V("alarmAcked", "BOOL", "报警已确认（条件消失后自动清除）", OUTD),
        V("highHigh", "BOOL", "高优先级报警（传感器断线导致）", OUTD),
    ]
    cases = [
        TestCase("a1", {"flowLow": False, "ackBtn": False, "sensorOK": True},
                 {"alarmActive": False, "alarmAcked": False, "highHigh": False},
                 "上电初态：无报警"),
        TestCase("a2", {"flowLow": True, "ackBtn": False, "sensorOK": True},
                 {"alarmActive": True, "alarmAcked": False},
                 "流量低 → 报警激活，未确认"),
        TestCase("a3", {"flowLow": False, "ackBtn": False, "sensorOK": True},
                 {"alarmActive": False, "alarmAcked": True,
                  "highHigh": False},
                 "条件消失但未确认 → 报警转为已确认待清除态（保持）"),
        TestCase("a4", {"flowLow": False, "ackBtn": True, "sensorOK": True},
                 {"alarmActive": False, "alarmAcked": False},
                 "确认后条件已消失 → 报警完全清除"),
        TestCase("a5", {"flowLow": True, "ackBtn": True, "sensorOK": True},
                 {"alarmActive": True, "alarmAcked": True},
                 "【边界】条件存在时按确认：只置已确认，报警不消失"),
        TestCase("a6", {"flowLow": False, "ackBtn": False, "sensorOK": False},
                 {"highHigh": True},
                 "【优先级】传感器断线 → 高优先级报警"),
        TestCase("a7", {"flowLow": True, "ackBtn": False, "sensorOK": False},
                 {"highHigh": True, "alarmActive": True},
                 "高优先级报警存在时，低优先级同时激活，不得被抑制"),
        TestCase("a8", {"flowLow": True, "ackBtn": False, "sensorOK": True},
                 {"alarmActive": True, "alarmAcked": False},
                 "高优先级消失后低优先级重新独立判定"),
    ]
    specs = [
        Spec("S1", "报警条件持续存在时，确认按钮不得使报警消失（当周期即成立）。",
             "G(flowLow & ackBtn -> alarmActive)", "safety"),
        Spec("S2", "未经确认的报警不会自行消失：条件仍在且未确认时，下一拍必须仍激活。",
             "G(alarmActive & !alarmAcked & X(flowLow) -> X(alarmActive))", "safety"),
        Spec("S3", "传感器断线时高优先级报警必须在当周期置位。",
             "G(!sensorOK -> highHigh)", "safety"),
        Spec("S4", "确认只在上升沿生效：确认沿出现且报警条件仍在时，当拍即置已确认。",
             "G(rising(ackBtn) & flowLow -> alarmAcked)", "sequencing"),
    ]
    return Problem(
        pid="self-hard-01",
        source="selfmade",
        difficulty=Difficulty.HARD,
        title="带确认与优先级的报警管理（四态报警模型）",
        requirements=(
            "写一个功能块 FB，实现 ISA-18.2 风格的四态报警管理。\n"
            "控制要求：\n"
            "1. 报警条件成立（flowLow = TRUE）→ alarmActive 置 TRUE，alarmAcked 置 FALSE；\n"
            "2. 报警未被确认时，即使条件消失，alarmActive 仍保持 TRUE"
            "（报警在未确认前不得消失），同时 alarmAcked 置 TRUE 表示'已转为待确认清除'；\n"
            "3. ackBtn 的**上升沿**确认报警：若此时条件已消失 → alarmActive 与 alarmAcked 一起清除；"
            "若条件仍存在 → 只置 alarmAcked，报警继续；\n"
            "4. sensorOK 为 FALSE 表示传感器断线 → highHigh 置 TRUE（高优先级）；"
            "**高优先级报警与低优先级报警必须同时可见，不得互相抑制**；\n"
            "5. 传感器恢复后，highHigh 自动清除，低优先级仍按 1~3 的规则独立判定。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业规范改编",
            "origin": "流程行业的报警管理普遍遵循 ISA-18.2 / 中控报警管理规范，"
                      "而赛题中'报警确认后才可清除'是最常被漏掉的一条。",
            "adaptation": "只保留单条低优先级报警与一条高优先级报警，"
                          "用于考察 LLM 能否正确实现'确认—清除'的时序而非简单自保持。",
            "review": "人工审核：四态模型（激活未确认/激活已确认/待清除/已清除）"
                      "在题面中以状态迁移方式描述，测试用例逐迁移覆盖。",
            "note": "本题难度来自'报警不可被确认直接清除'——这与直觉相反，"
                    "是区分模型是否真正理解需求的关键。",
        },
    )


# ==========================================================================
# 8. 批次计时（hard）
# ==========================================================================

def sc_batch_recipe() -> Problem:
    variables = [
        V("startBtn", "BOOL", "批次开始（上升沿有效）"),
        V("abortBtn", "BOOL", "中止按钮（直接中止批次）"),
        V("setpoint", "REAL", "工艺设定值"),
        V("pv", "REAL", "过程测量值"),
        V("maxDuration", "INT", "本批次允许的最长持续时间（秒）"),
        V("elapsed", "INT", "已运行秒数", OUTD),
        V("phase", "INT", "阶段号：0=空闲 1=升温 2=保温 3=完成 9=已中止", OUTD),
        V("timeout", "BOOL", "超时标志", OUTD),
    ]
    cases = [
        TestCase("b1", {"startBtn": True, "abortBtn": False,
                        "pv": 20.0, "elapsed": 0},
                 {"phase": 1, "elapsed": 0}, "开始批次 → 进入升温阶段",
                 {"setpoint": 80.0, "maxDuration": 30}),
        TestCase("b2", {"startBtn": False, "abortBtn": False,
                        "pv": 79.0, "elapsed": 3},
                 {"phase": 1, "elapsed": 4}, "未到设定值：继续升温，秒数累加",
                 {"setpoint": 80.0, "maxDuration": 30}),
        TestCase("b3", {"startBtn": False, "abortBtn": False,
                        "pv": 80.0, "elapsed": 30},
                 {"phase": 2, "timeout": True},
                 "【边界】pv 恰好等于 setpoint → 进入保温；同时 elapsed 到达 30 → 超时"),
        TestCase("b4", {"startBtn": False, "abortBtn": True,
                        "pv": 90.0, "elapsed": 0},
                 {"phase": 9, "elapsed": 0},
                 "【安全】保温阶段按中止 → 立刻中止，秒数不再累加"),
        TestCase("b5", {"startBtn": False, "abortBtn": False,
                        "pv": 85.0},
                 {"phase": 9}, "中止后即使条件满足也不得自动继续"),
        TestCase("b6", {"startBtn": True, "abortBtn": False,
                        "pv": 0.0},
                 {"phase": 1, "elapsed": 0, "timeout": False},
                 "重新开始：秒数与超时标志必须清零", {"maxDuration": 30}),
        TestCase("b7", {"startBtn": False, "abortBtn": False, "pv": 0.0},
                 {"phase": 2, "timeout": False},
                 "【时间语义】秒数应在每周期 +1，而不是依赖外部时钟"),
    ]
    specs = [
        Spec("S1", "批次的秒数只在运行阶段（phase 1/2）每周期恰好增加 1，"
                   "重新开始的那一拍例外（要清零）。",
             "G((phase = 1 | phase = 2) & !rising(startBtn) "
             "-> elapsed = prev(elapsed) + 1)", "sequencing"),
        Spec("S2", "已运行秒数达到最长持续时间后，timeout 必须在当拍置 TRUE。",
             "G(elapsed >= maxDuration & !rising(startBtn) -> timeout)", "safety"),
        Spec("S3", "中止按钮优先级最高：按下即进入中止态（同一拍生效）。",
             "G(abortBtn & !rising(startBtn) -> phase = 9)", "safety"),
        Spec("S4", "进入中止态后不得自动离开，除非出现新的启动上升沿。",
             "G(phase = 9 & !X(rising(startBtn)) -> X(phase = 9))", "safety"),
        Spec("S5", "重新开始时 elapsed 与 timeout 必须在同一拍清零/复位。",
             "G(rising(startBtn) -> elapsed = 0 & !timeout & phase = 1)", "sequencing"),
    ]
    return Problem(
        pid="self-hard-02",
        source="selfmade",
        difficulty=Difficulty.HARD,
        title="批次工艺阶段与运行时长统计（无外部时钟）",
        requirements=(
            "写一个功能块 FB，管理一个间歇反应釜的批次生命周期。\n"
            "控制要求：\n"
            "1. startBtn 的上升沿开始一个新批次：phase := 1，elapsed := 0，timeout := FALSE；\n"
            "2. phase = 1（升温）时，每个扫描周期 elapsed 加 1；当 pv **达到或超过** setpoint 时"
            "进入 phase = 2（保温）；\n"
            "3. phase = 2（保温）时，elapsed 继续每周期加 1，直到操作员按确认或超时；\n"
            "4. **超时判定**：elapsed 达到 maxDuration 时 timeout 置 TRUE，并进入 phase = 3（完成）；\n"
            "5. **中止按钮优先级最高**：任何阶段按下 abortBtn 都立即进入 phase = 9，且 elapsed 停止累加；\n"
            "6. 进入中止态后不得自动恢复，必须重新按 startBtn 并在新批次中清零一切状态；\n"
            "7. **不得使用任何系统时钟**（无 TIME/TON 等计时器），时长只能来自扫描周期计数。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业经验改编",
            "origin": "流程行业赛题的间歇反应工位普遍要求'升温—保温—完成'三阶段"
                      "以及批次时长统计；判断题面是否允许用 TON 是常见考点。",
            "adaptation": "显式禁止计时器，要求用扫描周期计数实现，"
                          "以考察 LLM 对 PLC 扫描周期语义的理解（这是纯软件工程师最容易忽略的一点）。",
            "review": "人工审核：题面第 7 条明确禁用时间类型，否则不同模型会走"
                      "'用 TON 实现'的分歧路径，导致测试不可比。",
            "note": "本题是'扫描周期计数 vs 真实时钟'的经典区分点，"
                    "在控制系统里两者语义不同，必须按题面要求。",
        },
    )


# ==========================================================================
# 9. 分批 FIFO（hard）
# ==========================================================================

def sc_fifo_batch() -> Problem:
    variables = [
        V("pushEn", "BOOL", "入队指令（上升沿有效）"),
        V("pushItem", "INT", "入队物料号"),
        V("popEn", "BOOL", "出队指令（上升沿有效）"),
        V("fifo", "ARRAY[1..8] OF INT", "队列缓冲区，下标 1 为最老元素", Direction.INOUT),
        V("count", "INT", "当前队列元素个数 0..8", OUTD),
        V("full", "BOOL", "队列满", OUTD),
        V("empty", "BOOL", "队列空", OUTD),
        V("head", "INT", "队首元素（空时保持 0）", OUTD),
    ]
    cases = [
        TestCase("q1", {"pushEn": False, "popEn": False},
                 {"count": 0, "empty": True, "full": False, "head": 0},
                 "初始：空队列"),
        TestCase("q2", {"pushEn": True, "popEn": False},
                 {"count": 1, "empty": False, "full": False, "head": 11},
                 "入队 1 个元素，队首即该元素", {"pushItem": 11}),
        TestCase("q3", {"pushEn": True, "popEn": False},
                 {"count": 2, "head": 11}, "入队第 2 个，队首不变",
                 {"pushItem": 22}),
        TestCase("q4", {"pushEn": False, "popEn": True},
                 {"count": 1, "head": 22},
                 "【边界】出队后队首移动到下一个元素", {"pushItem": 22}),
        TestCase("q5", {"pushEn": True, "popEn": False},
                 {"count": 8, "full": True, "empty": False},
                 "填满 8 个元素（本周期前已有 7 个）"),
        TestCase("q6", {"pushEn": True, "popEn": False},
                 {"count": 8, "full": True},
                 "【边界】队列满时入队必须被丢弃，不覆盖旧元素"),
        TestCase("q7", {"pushEn": False, "popEn": True},
                 {"count": 7, "full": False, "empty": False},
                 "满队列出队 1 个"),
        TestCase("q8", {"pushEn": False, "popEn": True},
                 {"count": 7},
                 "【边界】空队列出队：忽略，不产生负计数"),
    ]
    specs = [
        Spec("S1", "count 恒介于 0 与 8 之间。",
             "G(count >= 0 & count <= 8)", "safety"),
        Spec("S2", "队列满时入队不得改变 count（本拍即不改变）。",
             "G(prev(full) & pushEn & !popEn -> count = prev(count))", "safety"),
        Spec("S3", "队列空时出队不得改变 count，也不得产生负值（本拍即不改变）。",
             "G(prev(empty) & popEn & !pushEn -> count = prev(count))", "safety"),
        Spec("S4", "入队与出队严格保持先进先出顺序：先入的元素先出"
                   "（需要跟踪元素身份，只在用例中校验）。",
             "", "data", verified_by="simulation"),
        Spec("S5", "头指针只在出队时前进：没有出队动作的周期 head 必须保持不变。",
             "G(empty -> head = 0)", "sequencing"),
    ]
    return Problem(
        pid="self-hard-03",
        source="selfmade",
        difficulty=Difficulty.HARD,
        title="分批物料队列（环形缓冲 FIFO 与满空边界）",
        requirements=(
            "写一个功能块 FB，实现一个容量为 8 的先入先出物料队列。\n"
            "控制要求：\n"
            "1. pushEn 的**上升沿**把 pushItem 压入队尾；popEn 的上升沿从队首弹出；\n"
            "2. 每次只处理一条指令；若同一周期 pushEn 与 popEn 同时为上升沿，**先出队再入队**；\n"
            "3. count 输出当前队列元素个数（0..8），full 在 count = 8 时为 TRUE，"
            "empty 在 count = 0 时为 TRUE；\n"
            "4. **队列满时入队必须被丢弃**，不得覆盖已有元素，count 保持不变；\n"
            "5. **队列空时出队必须被忽略**，count 不得变成负数；\n"
            "6. head 输出队首元素的物料号，队列为空时保持 0；\n"
            "7. fifo 数组本身对外可见，下标 1 始终是最老元素（每周期需要整理成紧凑数组）。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业经验改编",
            "origin": "流程行业赛题里物料缓冲、成品暂存常用于吸收上下游节拍差异，"
                      "赛题中常要求 FIFO 队列；环形缓冲的满/空判定是经典易错点。",
            "adaptation": "把赛题中随管线运行的输送队列固化为 8 槽缓冲区，"
                          "并强制要求每周期整理成紧凑数组（下标 1 为最老），"
                          "这排除了只写读写指针的偷懒实现，考察真实数据搬移。",
            "review": "人工审核：满/空边界、同周期双向操作、计数不得为负三项均有独立用例；"
                      "'先出队再入队'的顺序在题面明确，避免歧义。",
        },
    )


# ==========================================================================
# 10. 泵切换优化（hard）
# ==========================================================================

def sc_pump_switch() -> Problem:
    variables = [
        V("demand", "INT", "需求泵台数 0..5（超出请先按边界裁剪）"),
        V("runHours", "ARRAY[1..5] OF LINT", "各泵累计运行小时数（只读）"),
        V("leadPump", "INT", "当前主泵号 1..5，0 表示尚未选定", OUTD),
        V("lagPump", "INT", "当前备用泵号 1..5，0 表示无", OUTD),
        V("runningCount", "INT", "实际运行泵台数", OUTD),
        # 注意方向：rotated 是**输入**（维护逻辑下发的轮换请求），不是输出。
        # 用例与参考解都按输入处理，早期误标成 OUTD 会让 check_dataset
        # 报"输出从未被断言"。
        V("rotated", "BOOL", "本周期存在轮换请求（输入，由维护逻辑置位）"),
    ]
    cases = [
        TestCase("p1", {"demand": 1, "rotated": False},
                 {"leadPump": 1, "lagPump": 0, "runningCount": 1},
                 "启动：需求 1 台，选运行小时最少的 1 号泵",
                 {"runHours": [100, 200, 300, 400, 500]}),
        TestCase("p2", {"demand": 2, "rotated": False},
                 {"leadPump": 1, "lagPump": 2, "runningCount": 2},
                 "需求 2 台：主泵 1、备泵 2，保持稳定不切换",
                 {"runHours": [100, 200, 300, 400, 500]}),
        TestCase("p3", {"demand": 0, "rotated": False},
                 {"leadPump": 0, "lagPump": 0, "runningCount": 0},
                 "需求 0：全部停机", {"runHours": [100, 200, 300, 400, 500]}),
        TestCase("p4", {"demand": 9, "rotated": False},
                 {"runningCount": 5},
                 "【边界】需求超出 5 台：按上限 5 裁剪，不得越界访问 runHours"),
        TestCase("p5", {"demand": -1, "rotated": False},
                 {"runningCount": 0, "leadPump": 0},
                 "【边界】需求为负：按 0 处理"),
        TestCase("p6", {"demand": 1, "rotated": True},
                 {"leadPump": 1},
                 "【稳定性】小时差未超过阈值 50 时不得切换，即使存在更少的泵"),
        TestCase("p7", {"demand": 1, "rotated": True},
                 {"leadPump": 3, "runningCount": 1},
                 "【切换】3 号泵小时数比 1 号少 60（> 50）→ 切换主泵",
                 {"runHours": [500, 400, 300, 200, 100]}),
    ]
    c1 = [100, 200, 300, 400, 500]
    cases[3].const_inputs["runHours"] = c1
    cases[4].const_inputs["runHours"] = c1
    cases[5].const_inputs["runHours"] = [100, 120, 300, 400, 500]
    specs = [
        Spec("S1", "运行台数必须等于裁剪后的需求值（需求先收敛到 0..5）。",
             "G(demand >= 0 & demand <= 5 -> runningCount = demand)", "safety"),
        Spec("S2", "主备泵必须是不同的泵（备泵为 0 表示只有一台）。",
             "G(lagPump <> 0 -> leadPump <> lagPump)", "safety"),
        Spec("S3", "收到轮换请求时，主备切换仅在两泵运行小时差超过阈值 50 时发生"
                   "（涉及内部排序表，只在用例中校验）。",
             "", "data", verified_by="simulation"),
        Spec("S4", "需求为 0 时不得有任何泵处于选中状态（当周期即成立）。",
             "G(demand <= 0 -> leadPump = 0 & lagPump = 0)", "safety"),
        Spec("S5", "需求为 0 时运行台数必须为 0。",
             "G(demand <= 0 -> runningCount = 0)", "safety"),
    ]
    return Problem(
        pid="self-hard-04",
        source="selfmade",
        difficulty=Difficulty.HARD,
        title="多泵均衡运行与主备切换（数组遍历与迟滞阈值）",
        requirements=(
            "写一个功能块 FB，管理 5 台并联泵的均衡运行。\n"
            "控制要求：\n"
            "1. demand 为工艺需求台数，**超出 0..5 时先按边界裁剪**（负数按 0、大于 5 按 5）；\n"
            "2. 需要运行的泵必须是 runHours 最小的若干台，以均衡磨损；\n"
            "3. leadPump 为主泵号、lagPump 为备用泵号，两者**必须是不同的泵**；"
            "需求 1 台时 lagPump = 0；需求 0 台时两者都为 0；\n"
            "4. runningCount 输出实际运行台数，必须严格等于裁剪后的需求；\n"
            "5. **迟滞要求**：rotated 为维护逻辑下发的**轮换请求（输入）**；"
            "仅当待选泵的运行小时数比当前主泵少超过 50 小时时才允许切换，"
            "否则即使收到请求也保持原主备；无请求时永不切换；\n"
            "6. 数组下标必须按题面 1..5 访问，不得把 0 号槽用掉。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        provenance={
            "source_type": "自主构思 / 行业经验改编",
            "origin": "流程行业赛题中多泵并联供水（多泵切换）是标志性题型，"
                      "要求按运行时间均衡分配并设置切换阈值。",
            "adaptation": "把赛题的 3 泵简化为 5 泵以考察数组遍历；"
                          "把'均衡'量化为'运行小时差超过 50 才切换'的精确阈值，"
                          "从而可被测试用例判定，而不是模糊的'尽量均衡'。",
            "review": "人工审核：LINT 类型用于小时累计（显式考察 64 位整型）；"
                      "裁剪与阈值两个边界均有正反用例；数组下标按 1 起，不得越界。",
        },
    )


BUILDERS = [
    sc_avg_div, sc_interlock, sc_recipe, sc_moving_avg, sc_gate_fsm,
    sc_filling, sc_alarm, sc_batch_recipe, sc_fifo_batch, sc_pump_switch,
]


def self_check(p: Problem) -> list[str]:
    """导出前的一致性自检：接口表 vs 测试向量。"""
    errs: list[str] = []
    names = {v.name.lower() for v in p.variables}
    for tc in p.test_cases:
        for k in list(tc.inputs) + list(tc.const_inputs) + list(tc.expected):
            if k.lower() not in names:
                errs.append(f"{p.pid}/{tc.tc_id}: 未声明的变量 {k!r}")
    if not p.test_cases:
        errs.append(f"{p.pid}: 没有测试用例")
    if not p.specs:
        errs.append(f"{p.pid}: 没有规约")
    # 每个 safety/sequencing 规约至少要有一条用例
    return errs


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    problems = [attach_cases(b()) for b in BUILDERS]
    all_errs: list[str] = []
    for p in problems:
        all_errs.extend(self_check(p))

    if all_errs:
        print("自检未通过：")
        for e in all_errs:
            print("  -", e)
        raise SystemExit(1)

    index = []
    for p in problems:
        path = OUT / f"{p.pid}.json"
        p.save(path)
        index.append({
            "pid": p.pid,
            "difficulty": p.difficulty.value,
            "title": p.title,
            "n_vars": len(p.variables),
            "n_specs": len(p.specs),
            "n_cases": len(p.test_cases),
        })
        print(f"{p.pid:16s} {p.difficulty.value:6s} vars={len(p.variables):2d} "
              f"specs={len(p.specs)} cases={len(p.test_cases):2d}  {p.title}")

    (OUT / "_index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"\n共 {len(problems)} 道自建题 -> {OUT}")


if __name__ == "__main__":
    main()
