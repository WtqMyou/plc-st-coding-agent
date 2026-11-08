# -*- coding: utf-8 -*-
"""队友新五题（P01~P05）的题目数据：self-hard-05 / self-medium-05 /
self-medium-06 / self-hard-06 / self-hard-07。

为什么单独一个文件
------------------
原来的 10 道题（``selfmade_build.py``）已经冻结并随 v1.1 交付，改它等于
把已验收的证据一起改掉。新五题先进这个文件，等全部跑绿、过完三道闸门
（参考解 / 数据集体检 / 模型检查）再合并进主线。

五道题都把队友文档里的"派生谓词"（如 ``inAuto``、``totalFlow``）显式写进
接口表或规约正文——原来的写法在规约里用了未声明变量，模型只能猜，规约
跑模型检查时直接"取不到值"，属于**题目缺陷**而非难度。

每道题都有一条及以上 ``verified_by="simulation"`` 的规约：数值计算/积分
递推这类"数据流性质"写成纯 LTL 会丢信息，只在轨迹用例里覆盖，并在报告
里如实标注（口径见 ``docs/`` 里的裁判能力边界说明）。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from stbench.schema import (  # noqa: E402
    Difficulty,
    Direction,
    Problem,
    Spec,
    TestCase,
    VarDef,
)

OUT = Path(__file__).resolve().parent / "selfmade"

IN = Direction.INPUT
OUTD = Direction.OUTPUT


def V(name: str, dtype: str, desc: str, direction=IN) -> VarDef:
    return VarDef(name=name, data_type=dtype, description=desc, direction=direction)


def seq(tc_id: str, inputs: dict, expected: dict, note: str) -> TestCase:
    """序列模式下的一条"扫描周期"：输入 + 本拍输出断言。"""
    return TestCase(tc_id, inputs, expected, note, {}, mode="sequence")


# ==========================================================================
# P01 self-hard-05 燃烧状态与氧量修正联锁
# ==========================================================================

def p01_flame_o2() -> Problem:
    variables = [
        V("runRequest", "BOOL", "燃烧运行请求"),
        V("flameOK", "BOOL", "火焰探测器反馈（TRUE=检测到火焰）"),
        V("o2Valid", "BOOL", "氧量分析仪数据有效"),
        V("o2PV", "REAL", "烟气含氧量测量值（%）"),
        V("baseAir", "REAL", "主风门基础开度给定（%），外部给定，自身不要求在 0..100"),
        V("resetBtn", "BOOL", "复位按钮（上升沿有效）"),
        V("fuelPermit", "BOOL", "燃料允许（联锁输出）", OUTD),
        V("trimEnable", "BOOL", "氧量修正投入（无故障才为 TRUE）", OUTD),
        V("airTrim", "REAL", "氧量修正偏置（%），钳位 ±10", OUTD),
        V("airCommand", "REAL", "风门开度命令（%），钳位 0..100", OUTD),
        V("tripLatched", "BOOL", "熄火跳闸自保持", OUTD),
        V("o2Fault", "BOOL", "氧量分析仪故障（无效或越界）", OUTD),
    ]
    cases = [
        seq("q1", {"runRequest": False, "flameOK": False, "o2Valid": True,
                   "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"o2Fault": False, "tripLatched": False, "fuelPermit": False,
             "trimEnable": False, "airTrim": 0.0, "airCommand": 0.0},
            "停机初始：无故障、不跳闸、无燃料许可，风门命令归 0"),
        seq("q2", {"runRequest": True, "flameOK": True, "o2Valid": True,
                   "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"o2Fault": False, "fuelPermit": True, "trimEnable": True,
             "airTrim": -4.0, "airCommand": 46.0},
            "正常运行：o2=4.0 → trim=2*(2-4)=-4，风门 46"),
        seq("q3", {"runRequest": True, "flameOK": False, "o2Valid": True,
                   "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"tripLatched": True, "fuelPermit": False, "trimEnable": False,
             "airTrim": 0.0, "airCommand": 0.0},
            "运行中熄火：**当拍**跳闸并切断燃料（不得等到下一拍）"),
        seq("q4", {"runRequest": True, "flameOK": True, "o2Valid": True,
                   "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"tripLatched": True, "fuelPermit": False, "trimEnable": False,
             "airTrim": 0.0, "airCommand": 0.0, "o2Fault": False},
            "跳闸自保持：火焰恢复也不自动复位；跳闸期间修正模块必须整段切除"
            "（trimEnable=FALSE、airTrim=0），风门命令归 0"),
        seq("q5", {"runRequest": False, "flameOK": False, "o2Valid": True,
                   "o2PV": 4.0, "baseAir": 50.0, "resetBtn": True},
            {"tripLatched": False, "fuelPermit": False, "airCommand": 0.0},
            "复位：runRequest=FALSE 且 flameOK=FALSE 时上升沿清除跳闸"),
        seq("q6", {"runRequest": True, "flameOK": True, "o2Valid": False,
                   "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"o2Fault": True, "fuelPermit": True, "trimEnable": False,
             "airTrim": 0.0, "airCommand": 50.0},
            "分析仪无效：切除修正但**不**切燃料，风门只跟基础给定"),
        seq("q7", {"runRequest": True, "flameOK": True, "o2Valid": True,
                   "o2PV": 1.0, "baseAir": 50.0, "resetBtn": False},
            {"o2Fault": False, "trimEnable": True, "airTrim": 2.0,
             "airCommand": 52.0},
            "恢复有效：o2 偏低 → 加风 +2"),
        seq("q8", {"runRequest": True, "flameOK": True, "o2Valid": True,
                   "o2PV": 5.5, "baseAir": 80.0, "resetBtn": False},
            {"airTrim": -7.0, "airCommand": 73.0},
            "o2 偏高 → trim=-7，风门 73"),
        seq("q9", {"runRequest": True, "flameOK": True, "o2Valid": True,
                   "o2PV": 8.0, "baseAir": 95.0, "resetBtn": False},
            {"airTrim": -10.0, "airCommand": 85.0},
            "【边界】原始 trim=2*(2-8)=-12，必须钳位到 -10"),
        seq("q10", {"runRequest": True, "flameOK": True, "o2Valid": True,
                    "o2PV": 1.0, "baseAir": 95.0, "resetBtn": False},
            {"airTrim": 2.0, "airCommand": 97.0},
            "正修正：95+2=97，尚在范围内"),
        seq("q11", {"runRequest": True, "flameOK": True, "o2Valid": True,
                    "o2PV": 0.0, "baseAir": 99.0, "resetBtn": False},
            {"airTrim": 4.0, "airCommand": 100.0},
            "【边界】99+4=103，风门命令必须钳位到 100"),
        seq("q12", {"runRequest": True, "flameOK": True, "o2Valid": True,
                    "o2PV": 21.0, "baseAir": 100.0, "resetBtn": False},
            {"o2Fault": False, "airTrim": -10.0, "airCommand": 90.0},
            "【边界】o2=21.0 仍属合法量程（<=21），trim 钳位 -10"),
        seq("q13", {"runRequest": True, "flameOK": True, "o2Valid": True,
                    "o2PV": 21.1, "baseAir": 100.0, "resetBtn": False},
            {"o2Fault": True, "trimEnable": False, "airTrim": 0.0,
             "airCommand": 100.0},
            "【边界】o2=21.1 越界 → 判故障、切除修正"),
        seq("q14", {"runRequest": True, "flameOK": True, "o2Valid": True,
                    "o2PV": -0.5, "baseAir": 50.0, "resetBtn": False},
            {"o2Fault": True, "fuelPermit": True, "trimEnable": False,
             "airTrim": 0.0, "airCommand": 50.0, "tripLatched": False},
            "o2Valid=TRUE 但 o2PV=-0.5 <0：同样判分析仪故障，切除修正但**不**切燃料"),
        seq("q15", {"runRequest": True, "flameOK": False, "o2Valid": True,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": True},
            {"tripLatched": True, "fuelPermit": False, "trimEnable": False,
             "airTrim": 0.0, "airCommand": 0.0, "o2Fault": False},
            "【非法复位】runRequest 仍为 TRUE 时按复位：即便有上升沿也不得清除跳闸"),
        seq("q16", {"runRequest": False, "flameOK": False, "o2Valid": True,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": True},
            {"tripLatched": True, "fuelPermit": False, "trimEnable": False,
             "airTrim": 0.0, "airCommand": 0.0},
            "【持续按住】条件虽已满足，但没有新的上升沿 → 跳闸保持"),
        seq("q17", {"runRequest": False, "flameOK": False, "o2Valid": True,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"tripLatched": True, "fuelPermit": False, "airCommand": 0.0},
            "【松开】复位键松开、无上升沿 → 跳闸仍保持"),
        seq("q18", {"runRequest": False, "flameOK": False, "o2Valid": True,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": True},
            {"tripLatched": False, "fuelPermit": False, "trimEnable": False,
             "airTrim": 0.0, "airCommand": 0.0, "o2Fault": False},
            "【合法复位】runRequest=FALSE 且 flameOK=FALSE 下的上升沿 → 清除跳闸"),
        seq("q19", {"runRequest": True, "flameOK": False, "o2Valid": True,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"tripLatched": True, "fuelPermit": False, "trimEnable": False,
             "airTrim": 0.0, "airCommand": 0.0, "o2Fault": False},
            "复位后再次运行中熄火 → 重新跳闸"),
        seq("q20", {"runRequest": False, "flameOK": True, "o2Valid": True,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": True},
            {"tripLatched": True, "fuelPermit": False, "trimEnable": False,
             "airTrim": 0.0, "airCommand": 0.0},
            "【非法复位】flameOK 仍为 TRUE（有火焰）时按复位 → 不得清除跳闸"),
        seq("q21", {"runRequest": True, "flameOK": False, "o2Valid": False,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"tripLatched": True, "o2Fault": True, "fuelPermit": False,
             "trimEnable": False, "airTrim": 0.0, "airCommand": 0.0},
            "熄火 + 分析仪失效同时发生：跳闸优先，修正切除"),
        seq("q22", {"runRequest": False, "flameOK": False, "o2Valid": True,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": True},
            {"tripLatched": False, "o2Fault": False, "fuelPermit": False,
             "trimEnable": False, "airTrim": 0.0, "airCommand": 0.0},
            "【恢复路径】再次合法复位 → 跳闸清除、故障不残留"),
        seq("q23", {"runRequest": True, "flameOK": True, "o2Valid": True,
                    "o2PV": 8.0, "baseAir": 5.0, "resetBtn": False},
            {"o2Fault": False, "tripLatched": False, "fuelPermit": True,
             "trimEnable": True, "airTrim": -10.0, "airCommand": 0.0},
            "【边界】风门下限：airTrim=-10 且 baseAir=5 → 合成 -5 钳位到 0，"
            "而 airTrim 本身仍是 -10（钳位作用在合成值上，不回写偏置）"),
        seq("q24", {"runRequest": False, "flameOK": False, "o2Valid": False,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"o2Fault": True, "tripLatched": False, "fuelPermit": False,
             "trimEnable": False, "airTrim": 0.0, "airCommand": 0.0},
            "停机态下分析仪失效：只报故障，不产生燃料许可、不跳闸"),
        seq("q25", {"runRequest": True, "flameOK": True, "o2Valid": True,
                    "o2PV": 4.0, "baseAir": 50.0, "resetBtn": False},
            {"o2Fault": False, "tripLatched": False, "fuelPermit": True,
             "trimEnable": True, "airTrim": -4.0, "airCommand": 46.0},
            "【恢复正常】o2 恢复 4.0、分析仪有效 → 修正重新投入，风门 46"),
    ]
    specs = [
        Spec("S1", "运行中失去火焰时，**同一周期**就必须跳闸（不得延迟一拍）。",
             "G((runRequest & !flameOK) -> tripLatched)", "safety"),
        Spec("S2", "跳闸一旦置位就自保持；只有\"runRequest=FALSE 且 flameOK=FALSE 下的复位上升沿\""
                    "这一个条件能清除它，其余任何一拍（含按住不复位、条件不满足时按复位）都必须保持。",
             "G((prev(tripLatched) & !(rising(resetBtn) & !runRequest & !flameOK)) -> tripLatched)",
             "safety"),
        Spec("S3", "跳闸状态下绝不允许燃料许可。",
             "G(tripLatched -> !fuelPermit)", "safety"),
        Spec("S4", "燃料许可的完整定义：运行请求、火焰正常、未跳闸三者同时成立才允许，缺一不可。",
             "G(fuelPermit <-> (runRequest & flameOK & !tripLatched))", "safety"),
        Spec("S5", "无燃料许可时风门命令必须归零（防止停机后残留开度）。",
             "G(!fuelPermit -> airCommand = 0.0)", "safety"),
        Spec("S6", "风门命令恒在 0..100 之间。",
             "G((airCommand >= 0.0) & (airCommand <= 100.0))", "safety"),
        Spec("S7", "氧量修正偏置恒在 ±10 之间。",
             "G((airTrim >= -10.0) & (airTrim <= 10.0))", "safety"),
        Spec("S8", "修正投入的完整定义：有燃料许可且分析仪无故障才投入；故障当拍即整段切除。",
             "G(trimEnable <-> (fuelPermit & !o2Fault))", "safety"),
        Spec("S9", "故障判据：数据无效、低于 0 或高于 21 三者任一成立。",
             "G(o2Fault <-> (!o2Valid | o2PV < 0.0 | o2PV > 21.0))", "safety"),
        Spec("S10", "修正切除时偏置必须归 0（不得残留上一次的修正量）。",
             "G(!trimEnable -> airTrim = 0.0)", "safety"),
        Spec("S11", "只有 o2PV > 7.0 一侧能触到负向限幅：此时偏置被钳在 -10。",
             "G((trimEnable & o2PV > 7.0) -> airTrim = -10.0)", "safety"),
        Spec("S12", "o2PV <= 7.0 一侧未达限幅：偏置严格等于 2.0*(2.0-o2PV)。",
             "G((trimEnable & o2PV <= 7.0) -> airTrim = 2.0 * (2.0 - o2PV))", "safety"),
        Spec("S13", "修正后合成开度超上限时命令钳在 100，且不改变偏置本身。",
             "G((fuelPermit & baseAir + airTrim > 100.0) -> airCommand = 100.0)", "safety"),
        Spec("S14", "修正后合成开度为负时命令钳在 0（baseAir 可以小于 10）。",
             "G((fuelPermit & baseAir + airTrim < 0.0) -> airCommand = 0.0)", "safety"),
        Spec("S15", "系数与钳位后的合成值：由仿真用例逐拍核对（净收益/风门数值语义）。", "",
             "data", verified_by="simulation"),
    ]
    return Problem(
        pid="self-hard-05",
        source="selfmade",
        difficulty=Difficulty.HARD,
        title="燃烧状态与氧量修正联锁（熄火跳闸 + 分析仪故障降级）",
        requirements=(
            "写一个功能块 FB，实现燃烧器的火焰联锁与烟气氧量修正。\n"
            "控制要求：\n"
            "1. 运行请求 runRequest 为 TRUE 且火焰探测器 flameOK 为 FALSE 时，"
            "**当拍**置位熄火跳闸 tripLatched，并切断燃料许可；\n"
            "2. tripLatched 自保持，只有在 runRequest=FALSE 且 flameOK=FALSE（停机且无火焰的安全态）"
            "的前提下，resetBtn 的**上升沿**才能清除。"
            "复位是边沿命令而不是保持命令：按住的时长不影响判定，每拍只认有没有新的上升沿；"
            "复位那一刻条件不满足就无效，之后条件满足了但还按着（没有新上升沿）也**不得**清除；"
            "runRequest 仍为 TRUE 或 flameOK 仍为 TRUE 时按下的复位同样无效；\n"
            "3. fuelPermit = runRequest AND flameOK AND NOT tripLatched；\n"
            "4. 氧量修正：trimEnable = fuelPermit AND NOT o2Fault；"
            "airTrim = 2.0 * (2.0 - o2PV)，并钳位到 [-10, +10]；"
            "trimEnable=FALSE 时 airTrim 必须为 0.0。"
            "说明：±10 是**输出约束**，不代表两个方向都能到饱和——合法量程 0..21% 内原始修正只在 "
            "[-38, +4] 之间（o2PV=0 得 +4，o2PV=21 得 -38），因此正向限幅在本题永远不触发，"
            "只有 o2PV > 7.0 时负向限幅才起作用；增益偏小属于演示取舍，"
            "真实装置的风门增益取决于风道流通能力；\n"
            "5. o2Fault = NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0"
            "（分析仪故障只切除修正，**不得**切除燃料；o2Valid=TRUE 但 o2PV<0 同样判故障）；\n"
            "6. airCommand = baseAir + airTrim，钳位到 [0, 100]；"
            "fuelPermit=FALSE 时 airCommand 必须为 0.0。"
            "说明：baseAir 是外部基础开度给定，本题**不要求** baseAir 自身落在 0..100，"
            "只要求最终 airCommand 落在 0..100（baseAir+airTrim 可能为负，此时钳位到 0）；\n"
            "7. 范围声明：本题只考核**运行阶段**的火焰联锁与氧量修正。"
            "预吹扫、点火、火焰建立等启动顺序，以及完整燃烧器安全管理（BMS，含吹扫时的风门要求）"
            "不在本题范围内，由其他系统负责。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        case_mode="sequence",
        provenance={
            "source_type": "队友评审草案改编（P01）",
            "origin": "2026 CIMC 流程行业自动化初赛样题中的燃烧控制环节："
                      "熄火保护与烟气氧量修正同时存在，两者对风门的处置相反。",
            "adaptation": "把原草案中的派生谓词（inAuto、o2TrimRaw 等）改为显式接口变量或"
                          "写进规约正文；去掉未声明的中间量，保证规约可直接判定。",
            "review": "人工审核：接口全为标量，无外部依赖；钳位与边沿语义与 IEC 61131-3 一致。",
        },
    )


# ==========================================================================
# P02 self-medium-05 合格蒸汽产量及净收益累计
# ==========================================================================

def p02_steam_profit() -> Problem:
    variables = [
        V("enable", "BOOL", "计量使能"),
        V("resetBtn", "BOOL", "清零按钮（上升沿有效）"),
        V("dt", "LREAL", "本周期时长（s），合法 0 < dt <= 10"),
        V("steamFlow", "LREAL", "蒸汽流量（kg/s），合法 0..90"),
        V("fuelFlow", "LREAL", "燃料流量（kg/s），合法 0..6"),
        V("steamTemp", "LREAL", "蒸汽温度（℃）"),
        V("steamPressure", "LREAL", "蒸汽压力（kPa）"),
        V("qualified", "BOOL", "本周期蒸汽是否合格", OUTD),
        V("dataFault", "BOOL", "数据故障（参数越界）", OUTD),
        V("qualifiedTon", "LREAL", "累计合格蒸汽产量（t）", OUTD),
        V("fuelTon", "LREAL", "累计燃料消耗（t）", OUTD),
        V("revenue", "LREAL", "累计收入（元）", OUTD),
        V("cost", "LREAL", "累计成本（元）", OUTD),
        V("netProfit", "LREAL", "累计净收益（元）", OUTD),
    ]
    cases = [
        seq("q1", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 20.0,
                   "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualified": True, "dataFault": False, "qualifiedTon": 0.02,
             "fuelTon": 0.001, "revenue": 5.6, "cost": 1.5, "netProfit": 4.1},
            "正常：q=20*1/1000=0.02t，f=1*1/1000=0.001t"),
        seq("q2", {"enable": True, "resetBtn": False, "dt": 2.0, "steamFlow": 20.0,
                   "fuelFlow": 1.0, "steamTemp": 446.0, "steamPressure": 3800.0},
            {"qualified": False, "dataFault": False, "qualifiedTon": 0.02,
             "fuelTon": 0.003, "revenue": 5.6, "cost": 4.5, "netProfit": 1.1},
            "温度 446 不合格：只累计燃料，不累计产量"),
        seq("q3", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 20.0,
                   "fuelFlow": 1.0, "steamTemp": 447.0, "steamPressure": 3750.0},
            {"qualified": True, "qualifiedTon": 0.04, "fuelTon": 0.004,
             "revenue": 11.2, "cost": 6.0, "netProfit": 5.2},
            "【边界】447.0 与 3750.0 恰好合格（闭区间）"),
        seq("q4", {"enable": True, "resetBtn": False, "dt": 0.0, "steamFlow": 20.0,
                   "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"dataFault": True, "qualifiedTon": 0.04, "fuelTon": 0.004,
             "netProfit": 5.2},
            "【边界】dt=0 判数据故障：本拍不累计；质量换算除的是固定 1000，"
            "这里不存在除零风险，dt=0 的意义是“程序周期数据无效”，不是除零"),
        seq("q5", {"enable": True, "resetBtn": True, "dt": 1.0, "steamFlow": 20.0,
                   "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualifiedTon": 0.0, "fuelTon": 0.0, "revenue": 0.0, "cost": 0.0,
             "netProfit": 0.0},
            "复位上升沿：累计量清零，当拍不累计"),
        seq("q6", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 0.0,
                   "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualifiedTon": 0.0, "fuelTon": 0.001, "revenue": 0.0, "cost": 1.5,
             "netProfit": -1.5},
            "只烧燃料不产汽：净收益为负，累计燃料照记"),
        seq("q7", {"enable": True, "resetBtn": False, "dt": 11.0, "steamFlow": 20.0,
                   "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"dataFault": True, "qualified": True, "qualifiedTon": 0.0,
             "fuelTon": 0.001, "revenue": 0.0, "cost": 1.5, "netProfit": -1.5},
            "【边界】dt=11 超上限 → 故障：本拍不累计，但判定位照常更新，累计燃料保持"),
        seq("q8", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 91.0,
                   "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"dataFault": True, "fuelTon": 0.001, "qualifiedTon": 0.0},
            "【边界】蒸汽流量 91 超量程 → 故障"),
        seq("q9", {"enable": True, "resetBtn": False, "dt": 2.0, "steamFlow": 90.0,
                   "fuelFlow": 6.0, "steamTemp": 453.0, "steamPressure": 3850.0},
            {"qualified": True, "dataFault": False, "qualifiedTon": 0.18,
             "fuelTon": 0.013, "revenue": 50.4, "cost": 19.5, "netProfit": 30.9},
            "【边界】四个量全部取合法上界：90*2/1000=0.18t，6*2/1000=0.012t"),
        seq("q10", {"enable": False, "resetBtn": False, "dt": 1.0, "steamFlow": 50.0,
                    "fuelFlow": 2.0, "steamTemp": 451.0, "steamPressure": 3800.0},
            {"qualified": True, "qualifiedTon": 0.18, "fuelTon": 0.013,
             "netProfit": 30.9},
            "enable=FALSE：只更新判定位，累计量保持（不得静默累加）"),
        seq("q11", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 50.0,
                    "fuelFlow": 6.1, "steamTemp": 451.0, "steamPressure": 3800.0},
            {"dataFault": True, "qualified": True, "qualifiedTon": 0.18,
             "fuelTon": 0.013, "revenue": 50.4, "cost": 19.5, "netProfit": 30.9},
            "【边界】燃料 6.1 超量程 → 故障：本拍不累计，累计量全部保持上拍值"),
        seq("q12", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 454.0, "steamPressure": 3700.0},
            {"qualified": False, "dataFault": False, "qualifiedTon": 0.18,
             "fuelTon": 0.014, "revenue": 50.4, "cost": 21.0, "netProfit": 29.4},
            "温度 454 高于上限 → 不合格：仍累计燃料、不累计产量"),
        seq("q13", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3851.0},
            {"qualified": False, "qualifiedTon": 0.18, "fuelTon": 0.015,
             "revenue": 50.4, "cost": 22.5, "netProfit": 27.9},
            "【边界】压力 3851 高于上限 → 不合格"),
        seq("q14", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3749.0},
            {"qualified": False, "qualifiedTon": 0.18, "fuelTon": 0.016,
             "revenue": 50.4, "cost": 24.0, "netProfit": 26.4},
            "【边界】压力 3749 低于下限 → 不合格"),
        seq("q15", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": -1.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualified": True, "dataFault": True, "qualifiedTon": 0.18,
             "fuelTon": 0.016, "revenue": 50.4, "cost": 24.0, "netProfit": 26.4},
            "负蒸汽流量 → 数据故障：本拍冻结，累计量保持"),
        seq("q16", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": -0.5, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"dataFault": True, "qualifiedTon": 0.18, "fuelTon": 0.016,
             "netProfit": 26.4},
            "负燃料流量 → 数据故障：冻结"),
        seq("q17", {"enable": True, "resetBtn": False, "dt": -1.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"dataFault": True, "qualifiedTon": 0.18, "fuelTon": 0.016,
             "netProfit": 26.4},
            "负扫描周期 → 数据故障：冻结（不得出现负增量）"),
        seq("q18", {"enable": True, "resetBtn": False, "dt": 10.0, "steamFlow": 10.0,
                    "fuelFlow": 0.5, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualified": True, "dataFault": False, "qualifiedTon": 0.28,
             "fuelTon": 0.021, "revenue": 78.4, "cost": 31.5, "netProfit": 46.9},
            "【边界】dt 恰好 10.0 合法：本次 +0.28×10/1000=0.1t 与 +0.5×10/1000=0.005t"),
        seq("q19", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": 0.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualified": True, "dataFault": False, "qualifiedTon": 0.30,
             "fuelTon": 0.021, "revenue": 84.0, "cost": 31.5, "netProfit": 52.5},
            "【边界】燃料流量恰好 0 合法（0 不是越界）：只产汽不耗燃料"),
        seq("q20", {"enable": True, "resetBtn": True, "dt": 0.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"dataFault": True, "qualifiedTon": 0.0, "fuelTon": 0.0,
             "revenue": 0.0, "cost": 0.0, "netProfit": 0.0},
            "【优先级】复位上升沿与数据故障同时发生：先清零，清零结果生效，"
            "故障位仍如实报出"),
        seq("q21", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"dataFault": False, "qualifiedTon": 0.02, "fuelTon": 0.001,
             "revenue": 5.6, "cost": 1.5, "netProfit": 4.1},
            "清零后恢复累计（故障消失）"),
        seq("q22", {"enable": True, "resetBtn": True, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualifiedTon": 0.0, "fuelTon": 0.0, "revenue": 0.0, "cost": 0.0,
             "netProfit": 0.0},
            "再次复位上升沿 → 清零"),
        seq("q23", {"enable": True, "resetBtn": True, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualifiedTon": 0.02, "fuelTon": 0.001, "revenue": 5.6, "cost": 1.5,
             "netProfit": 4.1},
            "【持续按住】没有新的上升沿 → 复位不再生效，恢复正常累计"),
        seq("q24", {"enable": True, "resetBtn": False, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualifiedTon": 0.04, "fuelTon": 0.002, "revenue": 11.2, "cost": 3.0,
             "netProfit": 8.2},
            "【松开】复位键松开 → 继续累计"),
        seq("q25", {"enable": True, "resetBtn": True, "dt": 1.0, "steamFlow": 20.0,
                    "fuelFlow": 1.0, "steamTemp": 450.0, "steamPressure": 3800.0},
            {"qualified": True, "dataFault": False, "qualifiedTon": 0.0,
             "fuelTon": 0.0, "revenue": 0.0, "cost": 0.0, "netProfit": 0.0},
            "【重新按下】松开后再按出上升沿 → 再次清零"),
    ]
    specs = [
        Spec("S1", "合格判据：温度 447..453 ℃ 且 压力 3750..3850 kPa（闭区间）。",
             "G(qualified <-> (steamTemp >= 447.0 & steamTemp <= 453.0 "
             "& steamPressure >= 3750.0 & steamPressure <= 3850.0))", "safety"),
        Spec("S2", "产量、燃料、收入、成本四项累计量永远非负（净收益不在此列，允许亏损）。",
             "G((qualifiedTon >= 0.0) & (fuelTon >= 0.0) & (revenue >= 0.0) "
             "& (cost >= 0.0))", "safety"),
        Spec("S3", "复位上升沿当拍把两个累计量清零。",
             "G(rising(resetBtn) -> (qualifiedTon = 0.0 & fuelTon = 0.0))", "safety"),
        Spec("S4", "数据故障判据：dt 不在 (0,10] 或流量越界。",
             "G(dataFault <-> (dt <= 0.0 | dt > 10.0 | steamFlow < 0.0 "
             "| steamFlow > 90.0 | fuelFlow < 0.0 | fuelFlow > 6.0))", "safety"),
        Spec("S5", "数据故障或未使能时，累计燃料在本拍保持不变。",
             "G((!rising(resetBtn) & (!enable | dataFault)) "
             "-> fuelTon = prev(fuelTon))", "safety"),
        Spec("S6", "数据故障且未复位时，累计产量在本拍保持不变。",
             "G((dataFault & !rising(resetBtn)) -> qualifiedTon = prev(qualifiedTon))",
             "safety"),
        Spec("S7", "金额三式恒成立：收入=产量×280、成本=燃料×1500、净收益=收入-成本。",
             "G((revenue = qualifiedTon * 280.0) & (cost = fuelTon * 1500.0) "
             "& (netProfit = revenue - cost))", "safety"),
        Spec("S9", "复位上升沿优先于故障冻结：复位与数据故障同拍时，累计量仍必须清零。",
             "G((rising(resetBtn) & dataFault) -> (qualifiedTon = 0.0 & fuelTon = 0.0))",
             "safety"),
        Spec("S10", "累计量按 flow*dt/1000 递推，收入=产量*280，成本=燃料*1500。", "",
             "data", verified_by="simulation"),
    ]
    return Problem(
        pid="self-medium-05",
        source="selfmade",
        difficulty=Difficulty.MEDIUM,
        title="合格蒸汽产量与净收益累计（闭区间判定 + 数据故障冻结）",
        requirements=(
            "写一个功能块 FB，按扫描周期累计锅炉的合格蒸汽产量、燃料消耗与净收益。\n"
            "控制要求：\n"
            "1. 合格判据：steamTemp 在 [447.0, 453.0] 且 steamPressure 在 "
            "[3750.0, 3850.0]（**闭区间**，端点合格；温度高于 453、压力低于 3750 "
            "或高于 3850 都判不合格）；\n"
            "2. 本周期合格且 enable=TRUE 且无数据故障时，"
            "qualifiedTon += steamFlow * dt / 1000.0（流量按 kg/s、周期按 s 计，"
            "kg/s × s ÷ 1000 = t）；"
            "无论是否合格，只要 enable 且无故障，fuelTon += fuelFlow * dt / 1000.0；\n"
            "3. 数据故障判据：dt <= 0.0 或 dt > 10.0（含恰好 10.0 合法、10.0 以上非法）"
            "或 steamFlow 不在 [0,90] 或 fuelFlow 不在 [0,6]（负流量同样判故障）；"
            "故障拍**不累计**，累计值保持不变；\n"
            "4. resetBtn 上升沿：两个累计量清零，且**当拍不再累计**。"
            "复位是边沿命令、不是保持命令：按住的时长不影响判定，每拍只认有没有新的上升沿。"
            "**复位优先于故障冻结**：同一拍同时出现复位上升沿与数据故障时，先执行清零，"
            "清零结果生效（故障位仍如实报出，但累计量不得停留在旧值）；\n"
            "5. revenue = qualifiedTon * 280.0，cost = fuelTon * 1500.0，"
            "netProfit = revenue - cost，三者每拍都要更新（即使不累计）。"
            "单价单位：蒸汽 280 元/t，燃料 1500 元/t，配 kg 换算后金额单位为元；\n"
            "6. qualifiedTon、fuelTon、revenue、cost 必须非负；"
            "netProfit **允许为负**（烧燃料不产汽时会亏损）。"
            "enable=FALSE 时只更新 qualified/dataFault 两个判定位，不改累计量。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        case_mode="sequence",
        provenance={
            "source_type": "队友评审草案改编（P02）",
            "origin": "流程行业锅炉产汽计量与能耗核算：合格判定与累计量的关系"
                      "在赛场上是高频错误点（把不合格蒸汽也算进产量）。",
            "adaptation": "原草案用派生谓词 totalFlow/steamOK 表达判据，改为直接对接口变量"
                          "写规约；补充 dt 越界与复位当拍不累计两条边界。",
            "review": "人工审核：纯标量接口；浮点比较用闭区间；LREAL 与 REAL 语义一致。",
        },
    )


# ==========================================================================
# P03 self-medium-06 温度模糊控制与输出约束
# ==========================================================================

def p03_fuzzy_temp() -> Problem:
    variables = [
        V("enable", "BOOL", "自动投入"),
        V("resetBtn", "BOOL", "复位（上升沿清除历史误差）"),
        V("sensorValid", "BOOL", "温度传感器数据有效"),
        V("setpoint", "REAL", "温度设定值（℃）"),
        V("temperature", "REAL", "温度测量值（℃）"),
        V("dt", "REAL", "本周期时长（s），合法 0 < dt <= 10"),
        V("bias", "REAL", "基础输出（%）"),
        V("power", "REAL", "加热功率输出（%），钳位 0..100", OUTD),
        V("correction", "REAL", "模糊修正量（%）", OUTD),
        V("fault", "BOOL", "传感器或参数故障", OUTD),
    ]
    cases = [
        seq("q1", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 50.0},
            {"fault": False, "correction": 20.0, "power": 70.0},
            "首拍无历史：de=0，e=10 → x=1.0/y=0 → 只踩 P×Z 规则（单点输出 20），修正 +20"),
        seq("q2", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 92.0, "dt": 1.0, "bias": 50.0},
            {"correction": 6.0, "power": 56.0},
            "e=8、de=(8-10)/1=-2 → x=0.8/y=-1：命中 Z×N(-10) 与 P×N(+10)，重心 = (-2+8)/1 = +6"),
        seq("q3", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 100.0, "dt": 1.0, "bias": 50.0},
            {"correction": -10.0, "power": 40.0},
            "e=0、de=-8 → 命中 Z×N，修正 -10（误差为零也要抑制负向趋势）"),
        seq("q4", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 98.0, "dt": 2.0, "bias": 50.0},
            {"correction": 9.0, "power": 59.0},
            "三邻域同时激活：e=2、de=1、dt=2 → x=0.2/y=0.5；"
            "隶属度 μZ(x)=0.8、μP(x)=0.2、μZ(y)=0.5、μP(y)=0.5 → "
            "Z×Z(0.8×0.5×0=0)、Z×P(0.8×0.5×10=4)、P×Z(0.2×0.5×20=2)、P×P(0.2×0.5×30=3)，"
            "权重和 0.4+0.4+0.1+0.1=1 → 修正 (0+4+2+3)/1 = 9.0"),
        seq("q5", {"enable": True, "resetBtn": False, "sensorValid": False,
                   "setpoint": 100.0, "temperature": 98.0, "dt": 1.0, "bias": 50.0},
            {"fault": True, "power": 0.0, "correction": 0.0},
            "传感器故障：功率与修正都归零，并清除历史误差"),
        seq("q6", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 100.0, "dt": 1.0, "bias": 50.0},
            {"fault": False, "correction": 0.0, "power": 50.0},
            "故障恢复首拍：历史已清除，按 de=0 处理，只出基础输出"),
        seq("q7", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 95.0},
            {"correction": 30.0, "power": 100.0},
            "【边界】上界：e=10、de=10 → x=1/y=1 → 只踩 P×P(30)；95+30=125 → "
            "power 钳位 100，而 correction 仍如实报 30"),
        seq("q8", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 110.0, "dt": 10.0, "bias": 5.0},
            {"correction": -30.0, "power": 0.0},
            "【边界】下界：e=-10、de=(-10-10)/10=-2 → x=-1/y=-1 → N×N(-30)；"
            "5-30=-25 → power 钳位 0；同时 dt=10.0 恰好是合法上界"),
        seq("q9", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 110.0, "dt": 11.0, "bias": 5.0},
            {"fault": True, "power": 0.0, "correction": 0.0},
            "【边界】dt=11 超出上限 → 故障、输出归零、清除历史"),
        seq("q10", {"enable": True, "resetBtn": False, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 110.0, "dt": 0.0, "bias": 50.0},
            {"fault": True, "power": 0.0, "correction": 0.0},
            "【边界】dt=0 → 故障（既不能除零，也不允许按 0 周期积分）"),
        seq("q11", {"enable": False, "resetBtn": False, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 50.0},
            {"fault": False, "power": 0.0, "correction": 0.0},
            "未投入自动：输出归零并清除历史"),
        seq("q12", {"enable": True, "resetBtn": False, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 110.0, "dt": 1.0, "bias": 30.0},
            {"fault": False, "correction": -20.0, "power": 10.0},
            "【恢复】禁用后重新投入的首拍：历史已清除 → de=0，"
            "x=-1/y=0 → 只踩 N×Z(-20)，30-20=10"),
        seq("q13", {"enable": True, "resetBtn": False, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 110.0, "dt": 1.0, "bias": 5.0},
            {"correction": -20.0, "power": 0.0},
            "【边界】下界侧：e=-10、de=0 → N×Z(-20)，5-20=-15 在范围内，不触发钳位"
            "（与 q8 的钳位对照，说明钳位只在越界时发生）"),
        seq("q14", {"enable": True, "resetBtn": True, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 50.0},
            {"fault": False, "power": 0.0, "correction": 0.0},
            "复位上升沿：输出与修正归零并清除历史"),
        seq("q15", {"enable": True, "resetBtn": True, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 50.0},
            {"correction": 20.0, "power": 70.0},
            "【持续按住】复位是边沿命令：没有新上升沿 → 不清零，恢复正常计算"
            "（历史已清 → de=0，只踩 P×Z=20）"),
        seq("q16", {"enable": True, "resetBtn": False, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 50.0},
            {"correction": 20.0, "power": 70.0},
            "【松开】复位键松开 → 继续按正常逻辑计算（e=10、de=0 → +20）"),
        seq("q17", {"enable": True, "resetBtn": True, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 50.0},
            {"power": 0.0, "correction": 0.0},
            "【重新按下】松开后再按出上升沿 → 再次清零"),
        seq("q18", {"enable": True, "resetBtn": False, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 100.0, "dt": 1.0, "bias": 50.0},
            {"fault": False, "correction": 0.0, "power": 50.0},
            "【复位后恢复】历史确已清除：e=0、de=0（若历史未清则 de=(0-10)/1=-10 → -10）"
            " → 只踩 Z×Z=0，功率=基础给定 50"),
    ]
    specs = [
        Spec("S1", "加热功率恒在 0..100 之间。",
             "G((power >= 0.0) & (power <= 100.0))", "safety"),
        Spec("S2", "模糊修正量恒在 ±30 之间（九个单点输出量的极值）。",
             "G((correction >= -30.0) & (correction <= 30.0))", "safety"),
        Spec("S3", "未投入、复位上升沿或故障时，输出与修正必须归零。",
             "G((!enable | rising(resetBtn) | fault) -> "
             "(power = 0.0 & correction = 0.0))", "safety"),
        Spec("S4", "故障判据：传感器无效或 dt 越界。",
             "G(fault <-> (!sensorValid | dt <= 0.0 | dt > 10.0))", "safety"),
        Spec("S5", "传感器无效必然判故障（不允许用坏数据继续闭环）。",
             "G(!sensorValid -> fault)", "safety"),
        Spec("S7", "故障/禁用之后重新计算的首拍，历史必须已清除：误差为正且超过满量程时"
                   "只踩 P×Z 一条规则，修正恰为 +20（若历史未清，de 会带出别的值）。",
             "G(((prev(fault) | prev(!enable)) & enable & !fault & !rising(resetBtn) "
             "& setpoint - temperature >= 10.0) -> correction = 20.0)", "safety"),
        Spec("S8", "故障/禁用之后重新计算的首拍，误差为 0 时修正必须为 0"
                   "（历史未清则会因 de≠0 给出非零修正）。",
             "G(((prev(fault) | prev(!enable)) & enable & !fault & !rising(resetBtn) "
             "& setpoint = temperature) -> correction = 0.0)", "safety"),
        Spec("S9", "复位不是保持命令：按住复位（无新上升沿）时不得继续强制清零，"
                   "必须按正常模糊逻辑出功率。",
             "G((resetBtn & prev(resetBtn) & !fault & enable & (bias > 0.0) "
             "& setpoint - temperature >= 10.0) -> power > 0.0)", "safety"),
        Spec("S10", "功率 = 基础输出 + 修正后再钳位。", "",
             "data", verified_by="simulation"),
    ]
    return Problem(
        pid="self-medium-06",
        source="selfmade",
        difficulty=Difficulty.MEDIUM,
        title="温度模糊控制与输出钳位（重心法 + 历史误差清除）",
        requirements=(
            "写一个功能块 FB，用九条规则的温度模糊控制器计算加热功率。\n"
            "控制要求：\n"
            "1. e = setpoint - temperature；de = (e - ePrev) / dt，**首拍**或历史被清除时 de = 0；\n"
            "2. x = clamp(e / 10.0, -1, 1)，y = clamp(de / 2.0, -1, 1)。"
            "量程说明：±10 ℃ 与 ±2 ℃/s 是本演示的满量程假设（对应温度回路约 ±10 ℃、"
            "变化率 ±2 ℃/s 的振荡工况；按幅值 ±10 ℃、周期 31.4 s 估算，"
            "变化率峰值约 2.0 ℃/s，该假设在演示工况下自洽），"
            "换到真实装置应按实际量程重新整定；\n"
            "3. 隶属度：μN(z)=max(-z,0)、μZ(z)=1-|z|、μP(z)=max(z,0)；\n"
            "4. 九条规则的单点输出：N×N=-30、N×Z=-20、N×P=-10、Z×N=-10、Z×Z=0、"
            "Z×P=10、P×N=10、P×Z=20、P×P=30；"
            "correction = Σ(w·c)/Σw（重心法），Σw=0 时 correction=0；\n"
            "5. power = clamp(bias + correction, 0, 100)，**correction 不钳位**；\n"
            "6. fault = NOT sensorValid OR dt <= 0.0 OR dt > 10.0；"
            "fault、enable=FALSE 或 resetBtn **上升沿**时：power=0、correction=0，"
            "并清除历史（ePrev=0、历史标志=FALSE）。"
            "复位是边沿命令、不是停机保持命令：按住的时长不影响判定，每拍只认有没有新的上升沿；"
            "按住复位期间输出的 0 只在上升沿那一拍成立，之后回到正常模糊计算"
            "（历史已清除，所以恢复后的首拍按 de=0 处理）。"
            "“首拍/复位后/故障或禁用后恢复的首拍”指历史标志为 FALSE 的那一拍，"
            "该拍 ePrev 不参与，de 一律取 0；下一拍起才用正常差分。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        case_mode="sequence",
        provenance={
            "source_type": "队友评审草案改编（P03）",
            "origin": "温控回路里用模糊修正替代固定 PID 微调，是流程行业常见的"
                      "低成本改造；难点在重心法与历史误差的清除时机。",
            "adaptation": "原草案把 ABS/MAX 写成派生函数，改为标准库函数调用；"
                          "补充 dt 越界与钳位边界用例。",
            "review": "人工审核：九条规则的权重和恒为 1（z=0 时退化），"
                      "重心法在边界上连续；已用参考解逐拍核对。",
        },
    )


# ==========================================================================
# P04 self-hard-06 蒸汽超压联锁与故障线索诊断
# ==========================================================================

def p04_overpressure() -> Problem:
    variables = [
        V("runRequest", "BOOL", "运行请求"),
        V("pressure", "REAL", "母管压力（kPa）"),
        V("pressureValid", "BOOL", "压力变送器数据有效"),
        V("fuelFlow", "REAL", "燃料流量（t/h）"),
        V("steamFlow", "REAL", "蒸汽流量（t/h）"),
        V("outletCmd", "INT", "减温减压阀开度命令（%）"),
        V("outletFeedback", "INT", "减温减压阀开度反馈（%）"),
        V("resetBtn", "BOOL", "复位按钮（上升沿有效）"),
        V("tripLatched", "BOOL", "超压跳闸自保持", OUTD),
        V("fuelPermit", "BOOL", "燃料许可", OUTD),
        V("currentCauseMask", "WORD", "本周期诊断线索位掩码", OUTD),
        V("latchedCauseMask", "WORD", "跳闸期间线索累积掩码（全历史足迹）", OUTD),
        V("diagnosticActive", "BOOL", "存在有效诊断线索", OUTD),
    ]

    def c(tc_id, run, p, valid, fuel, steam, cmd, fb, reset, exp, note):
        return seq(tc_id,
                   {"runRequest": run, "pressure": p, "pressureValid": valid,
                    "fuelFlow": fuel, "steamFlow": steam, "outletCmd": cmd,
                    "outletFeedback": fb, "resetBtn": reset}, exp, note)

    cases = [
        c("q1", False, 4000.0, True, 1.0, 20.0, 0, 0, False,
          {"tripLatched": False, "fuelPermit": False, "currentCauseMask": 0,
           "latchedCauseMask": 0, "diagnosticActive": False},
          "停机初始：无跳闸、无线索"),
        c("q2", True, 4200.0, True, 2.0, 20.0, 60, 60, False,
          {"tripLatched": False, "fuelPermit": True, "currentCauseMask": 0},
          "压力 4200 未达 4500：允许燃料，无线索"),
        c("q3", True, 4600.0, True, 2.0, 20.0, 60, 60, False,
          {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 8,
           "latchedCauseMask": 8, "diagnosticActive": True},
          "超压但阀位正常、燃烧正常 → 线索=8（未定位）"),
        c("q4", True, 4600.0, True, 2.0, 20.0, 80, 0, False,
          {"tripLatched": True, "currentCauseMask": 8, "latchedCauseMask": 8},
          "阀卡滞第 1 拍（计数 1，未达 3 拍判据）仍只报 8"),
        c("q5", True, 4600.0, True, 4.5, 5.0, 80, 0, False,
          {"currentCauseMask": 4, "latchedCauseMask": 12},
          "阀计数 2 + 燃烧过剩 → 位2 已置（8|4=12）"),
        c("q6", True, 4600.0, True, 4.5, 5.0, 80, 0, False,
          {"currentCauseMask": 6, "latchedCauseMask": 14},
          "阀计数达 3 → 位1 置；与位2 合并得 6（14=8|4|2）"),
        c("q7", False, 4000.0, True, 0.0, 0.0, 0, 0, False,
          {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 0,
           "latchedCauseMask": 14, "diagnosticActive": False},
          "停机后本拍无线索，但**已累积**的足迹必须保留（供事后诊断）"),
        c("q8", False, 4000.0, True, 0.0, 0.0, 0, 0, True,
          {"tripLatched": False, "currentCauseMask": 0, "latchedCauseMask": 0},
          "复位：runRequest=FALSE、压力已回落到 <=4200 → 跳闸与足迹一起清"),
        c("q9", True, 4600.0, True, 4.5, 5.0, 0, 0, False,
          {"tripLatched": True, "currentCauseMask": 4, "latchedCauseMask": 4},
          "阀命令未达 50 → 不计卡滞；只剩燃烧过剩线索"),
        c("q10", True, 4600.0, False, 4.5, 5.0, 90, 0, False,
          {"tripLatched": True, "currentCauseMask": 1, "latchedCauseMask": 5},
          "变送器失效：线索=1（优先于压力判据），并入累积 5"),
        # ---- 复核补充：失效率拍独立触发、恢复后线索清零、复位许可边界 ----
        c("q11", True, 4000.0, True, 2.0, 20.0, 60, 60, False,
          {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 0,
           "latchedCauseMask": 5, "diagnosticActive": False},
          "变送器恢复、压力回落到 4000：本拍线索清零，历史足迹 5 仍保留"),
        c("q12", True, 4100.0, True, 2.0, 20.0, 60, 60, True,
          {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 0,
           "latchedCauseMask": 5},
          "非法复位：有上升沿但 runRequest 仍为 TRUE → 不得清除"),
        c("q13", False, 4100.0, True, 0.0, 0.0, 0, 0, True,
          {"tripLatched": True, "currentCauseMask": 0, "latchedCauseMask": 5},
          "复位持续按住、条件（停机）后来才满足但没有新的上升沿 → 仍不得清除"),
        c("q14", False, 4100.0, True, 0.0, 0.0, 0, 0, False,
          {"tripLatched": True, "currentCauseMask": 0, "latchedCauseMask": 5,
           "diagnosticActive": False},
          "松开复位：跳闸保持，足迹不变"),
        c("q15", False, 4201.0, True, 0.0, 0.0, 0, 0, True,
          {"tripLatched": True, "currentCauseMask": 0, "latchedCauseMask": 5},
          "【边界】新上升沿但压力 4201 > 4200 → 复位许可不满足，不得清除"),
        c("q16", False, 4200.0, True, 0.0, 0.0, 0, 0, False,
          {"tripLatched": True, "currentCauseMask": 0, "latchedCauseMask": 5},
          "松开复位、压力回到 4200：仍保持（清除只认上升沿）"),
        c("q17", False, 4200.0, True, 0.0, 0.0, 0, 0, True,
          {"tripLatched": False, "fuelPermit": False, "currentCauseMask": 0,
           "latchedCauseMask": 0, "diagnosticActive": False},
          "【边界】恰好 4200（含端点）+ 新上升沿 → 跳闸与足迹一起清"),
        # ---- 复核补充：4500/4499 阈值边界、单独 bit1、计数清零的四种途径 ----
        c("q18", True, 4499.0, True, 2.0, 20.0, 60, 60, False,
          {"tripLatched": False, "fuelPermit": True, "currentCauseMask": 0,
           "diagnosticActive": False},
          "【边界】4499 < 4500 → 不跳闸、无线索、燃料许可"),
        c("q19", True, 4500.0, True, 2.0, 20.0, 60, 60, False,
          {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 8,
           "latchedCauseMask": 8, "diagnosticActive": True},
          "【边界】恰好 4500（含端点）→ 当拍跳闸，线索=8"),
        c("q20", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"tripLatched": True, "currentCauseMask": 8, "latchedCauseMask": 8},
          "【边界】outletCmd=50、outletFeedback=10 都含端点 → 计 1 拍，未达 3 拍仍报 8"),
        c("q21", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 8, "latchedCauseMask": 8},
          "卡滞第 2 拍（连续）→ 计数 2，仍未达判据"),
        c("q22", True, 4600.0, True, 2.0, 20.0, 50, 30, False,
          {"currentCauseMask": 8, "latchedCauseMask": 8},
          "中途反馈恢复（10→30）：连续 3 拍被打破 → 计数清零，仍只报 8"),
        c("q23", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 8, "latchedCauseMask": 8},
          "重新计第 1 拍（清零后从头算）"),
        c("q24", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 8, "latchedCauseMask": 8},
          "重新计第 2 拍"),
        c("q25", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 2, "latchedCauseMask": 10},
          "第 3 拍达标 → **单独出现 bit1=2**（有线索故不置 bit3），足迹 8|2=10"),
        c("q26", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 2, "latchedCauseMask": 10},
          "连续第 4 拍（超过 3 拍）：仍只报 2，计数饱和不溢出"),
        c("q27", True, 4400.0, True, 2.0, 20.0, 50, 10, False,
          {"tripLatched": True, "currentCauseMask": 0, "latchedCauseMask": 10,
           "diagnosticActive": False},
          "压力回落到 4400（不再超压）→ 卡滞计数清零、本拍无线索，跳闸与足迹保持"),
        c("q28", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"tripLatched": True, "currentCauseMask": 8, "latchedCauseMask": 10},
          "再次超压 + 卡滞第 1 拍：若压力回落时没清零会误报 2，这里只报 8"),
        c("q29", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 8, "latchedCauseMask": 10},
          "卡滞第 2 拍（连续）"),
        c("q30", True, 4600.0, False, 2.0, 20.0, 50, 10, False,
          {"tripLatched": True, "currentCauseMask": 1, "latchedCauseMask": 11,
           "diagnosticActive": True},
          "变送器失效打断卡滞计数：线索=1，足迹 10|1=11，跳闸保持"),
        c("q31", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 8, "latchedCauseMask": 11},
          "变送器恢复后卡滞从第 1 拍重新计数（失效期间的中断已被清零）"),
        c("q32", False, 4600.0, True, 0.0, 0.0, 0, 0, False,
          {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 0,
           "latchedCauseMask": 11, "diagnosticActive": False},
          "停止运行打断计数：本拍线索=0、计数清零，跳闸与足迹保持"),
        c("q33", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 8, "latchedCauseMask": 11},
          "重新运行 + 卡滞第 1 拍：计数从 0 起（停机期间已清零）"),
        c("q34", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 8, "latchedCauseMask": 11},
          "卡滞第 2 拍"),
        c("q35", True, 4600.0, True, 2.0, 20.0, 50, 10, False,
          {"currentCauseMask": 2, "latchedCauseMask": 11},
          "卡滞第 3 拍 → bit1 置；足迹 11 本来就含位1，按位或后仍是 11"),
        c("q36", True, 4600.0, True, 4.0, 10.0, 50, 10, False,
          {"currentCauseMask": 6, "latchedCauseMask": 15},
          "【边界】fuelFlow=4.0、steamFlow=10.0 都含端点 → 燃烧过剩成立，6=2|4，足迹 15"),
        c("q37", True, 4600.0, True, 3.9, 10.0, 50, 10, False,
          {"currentCauseMask": 2, "latchedCauseMask": 15},
          "【边界】fuelFlow=3.9 < 4.0 → 不判燃烧过剩，只剩 bit1"),
        c("q38", True, 4600.0, True, 4.0, 10.1, 50, 10, False,
          {"currentCauseMask": 2, "latchedCauseMask": 15},
          "【边界】steamFlow=10.1 > 10.0 → 不判燃烧过剩"),
        c("q39", True, 4600.0, True, 5.0, 5.0, 0, 0, False,
          {"currentCauseMask": 4, "latchedCauseMask": 15},
          "只有燃烧过剩（阀命令未达 50）→ 4；足迹 15|4 仍为 15"),
        c("q40", True, 4600.0, True, 2.0, 20.0, 60, 60, False,
          {"currentCauseMask": 8, "latchedCauseMask": 15},
          "超压但一切正常 → 未定位 8；累积时 15|8 仍为 15"),
        c("q41", False, 4000.0, True, 0.0, 0.0, 0, 0, True,
          {"tripLatched": False, "fuelPermit": False, "currentCauseMask": 0,
           "latchedCauseMask": 0, "diagnosticActive": False},
          "停机 + 合法复位 → 跳闸与全部足迹清零"),
        c("q42", True, 4000.0, False, 2.0, 20.0, 60, 60, False,
          {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 1,
           "latchedCauseMask": 1, "diagnosticActive": True},
          "**从未跳闸的干净状态**起：压力本身只有 4000 kPa，仅靠 pressureValid=FALSE "
          "就独立触发跳闸（线索=1），证明失效路径不依赖压力判据"),
        c("q43", False, 4000.0, True, 0.0, 0.0, 0, 0, True,
          {"tripLatched": False, "fuelPermit": False, "currentCauseMask": 0,
           "latchedCauseMask": 0, "diagnosticActive": False},
          "收尾：停机 + 合法复位 → 清零"),
        c("q44", True, 4200.0, False, 0.0, 0.0, 0, 0, False,
          {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 1,
           "latchedCauseMask": 1, "diagnosticActive": True},
          "压力 4200 本不越限，但**变送器失效**按最坏情况处理 → 独立跳闸（线索=1）"),
        c("q45", True, 4200.0, False, 0.0, 0.0, 0, 0, True,
          {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 1,
           "latchedCauseMask": 1},
          "复位上升沿 + 变送器失效：复位许可要求数据有效 → 跳闸不得清除"),
    ]
    specs = [
        Spec("S1", "压力变送器失效且仍在运行时，必须当拍跳闸并切除燃料。",
             "G((runRequest & !pressureValid) -> (tripLatched & !fuelPermit))", "safety"),
        Spec("S2", "母管压力达到 4500 kPa（数据有效）时必须当拍跳闸。",
             "G((runRequest & pressureValid & pressure >= 4500.0) -> tripLatched)",
             "safety"),
        Spec("S3", "跳闸状态下绝不允许燃料许可。",
             "G(tripLatched -> !fuelPermit)", "safety"),
        Spec("S4", "跳闸自保持：没有复位上升沿时不得自行解锁。",
             "G((prev(tripLatched) & !rising(resetBtn)) -> tripLatched)", "safety"),
        Spec("S4b", "存在复位上升沿但复位许可条件（停机 + 数据有效 + 压力 <= 4200）"
                    "不满足时，跳闸也不得解锁。",
             "G((prev(tripLatched) & rising(resetBtn) & "
             "(runRequest OR !pressureValid OR pressure > 4200.0)) -> tripLatched)",
             "safety"),
        Spec("S5", "无运行请求时本周期线索掩码必须为 0。",
             "G(!runRequest -> currentCauseMask = 0)", "safety"),
        Spec("S6", "压力未越限且数据有效时不产生线索。",
             "G((runRequest & pressureValid & pressure < 4500.0) -> "
             "currentCauseMask = 0)", "safety"),
        Spec("S7", "诊断有效位与线索掩码一致。",
             "G(diagnosticActive <-> currentCauseMask <> 0)", "safety"),
        Spec("S8", "合法复位（上升沿 + 停机 + 数据有效 + 压力 <= 4200）必须同时清除"
                   "跳闸与线索足迹。",
             "G((rising(resetBtn) & !runRequest & pressureValid & pressure <= 4200.0) "
             "-> (!tripLatched & latchedCauseMask = 0))", "safety"),
        Spec("S9", "bit3（未定位，掩码恰为 8）只出现在运行中的超压工况。",
             "G(currentCauseMask = 8 -> (runRequest & pressureValid & "
             "pressure >= 4500.0))", "safety"),
        Spec("S10", "bit2（燃烧过剩）成立时必然满足燃料流量偏高、蒸汽流量偏低的判据。",
             "G((currentCauseMask = 4 OR currentCauseMask = 6 OR "
             "currentCauseMask = 12 OR currentCauseMask = 14) -> "
             "(fuelFlow >= 4.0 & steamFlow <= 10.0))", "safety"),
        Spec("S11", "bit1（阀卡滞）成立时必然满足阀命令/反馈的卡滞判据。",
             "G((currentCauseMask = 2 OR currentCauseMask = 6 OR "
             "currentCauseMask = 10 OR currentCauseMask = 14) -> "
             "(outletCmd >= 50 & outletFeedback <= 10))", "safety"),
        Spec("S12", "bit0 只在运行中变送器失效时出现，且失效当拍掩码恰为 1。",
             "G((runRequest & !pressureValid) -> currentCauseMask = 1)", "safety"),
        Spec("S13", "跳闸期间线索足迹只增不减（按位或累积，不复位不清零）。",
             "G((prev(tripLatched) & tripLatched) -> "
             "latchedCauseMask >= prev(latchedCauseMask))", "safety"),
        Spec("S14", "线索位含义、卡滞连续 3 拍判据（中断/压力回落/失效/停机均清零）、"
                    "足迹累积与复位清零的完整行为。", "",
             "data", verified_by="simulation"),
    ]
    return Problem(
        pid="self-hard-06",
        source="selfmade",
        difficulty=Difficulty.HARD,
        title="蒸汽母管超压联锁与故障线索诊断（按位编码 + 足迹保留）",
        requirements=(
            "写一个功能块 FB，实现母管超压联锁，并在跳闸时记录**故障线索**。\n"
            "控制要求：\n"
            "1. 压力有效判据 pressureValid；>= 4500.0 kPa 判超压；\n"
            "2. 跳闸条件（任一成立）：runRequest 且 pressureValid 且 pressure >= 4500.0；"
            "runRequest 且 NOT pressureValid（数据失效按最坏情况处理）；"
            "跳闸与本拍线索同拍生效；\n"
            "3. tripLatched 自保持；清除条件：resetBtn 上升沿 且 NOT runRequest 且 "
            "pressureValid 且 pressure <= 4200.0。4500 与 4200 之间的 300 kPa 是"
            "**滞环**：跳闸整定取母管额定压力（约 4.0 MPa）之上 500 kPa，复位门槛再"
            "回退 300 kPa，防止压力在阈值附近抖动导致反复跳闸/复位；\n"
            "4. 线索位（currentCauseMask，WORD 的**低 4 位**，本拍重新计算）：\n"
            "   bit0=1 变送器失效（runRequest 且 NOT pressureValid）；\n"
            "   bit1=2 减温减压阀卡滞：outletCmd>=50 且 outletFeedback<=10 **连续 3 个"
            "执行周期及以上**；\n"
            "   bit2=4 燃烧过剩：fuelFlow >= 4.0 且 steamFlow <= 10.0"
            "（比较的是接口流量数值，单位 t/h；两个边界都含等于）；\n"
            "   bit1/bit2 只在「runRequest 且 pressureValid 且 pressure >= 4500.0」的"
            "超压工况下评估；若超压但以上线索都不成立，置 bit3=8（未定位）；\n"
            "   NOT runRequest 时线索为 0；\n"
            "5. 卡滞判据必须是**连续扫描周期**：中途反馈恢复、压力回落到 4500 以下、"
            "变送器失效或 runRequest=FALSE，都要把 3 拍计数清零——计数不清零就会把"
            "历史误当成“连续”；\n"
            "6. latchedCauseMask：tripLatched 为 TRUE 时把 currentCauseMask **按位或**"
            "并入。注意 WORD 是 **16 位**（DWORD 才是 32 位），本题只用低 4 位"
            "（最大 15），16 位足够、不会溢出。该掩码保存的是“本次跳闸期间**全部历史"
            "线索的累积**”，**不是**跳闸瞬间的原因快照——跳闸后新出现的线索也会并入，"
            "只有合法复位才清零；因此它回答的是“这次跳闸期间一共观察到过哪些现象”，"
            "不能把它直接当成唯一的跳闸原因；\n"
            "7. fuelPermit = runRequest AND NOT tripLatched；"
            "diagnosticActive = (currentCauseMask <> 0)。\n"
            "取数与整定说明：\n"
            "- 本块每个扫描周期执行一次，题目不定义扫描周期时长：“连续 3 拍”指连续"
            "3 个执行周期，不承诺固定秒数；\n"
            "- 4500/4200 kPa 与 300 kPa 滞环是该算例的整定值（母管额定约 4.0 MPa，"
            "超压保护整定在其上 500 kPa，复位门槛回退 300 kPa），只用于考核联锁逻辑，"
            "不代表具体机组的最终整定；工程整定须依据母管设计压力与安全阀铭牌；\n"
            "- 燃烧过剩判据 4.0/10.0 t/h 是“燃料流量偏高而蒸汽流量偏低”的算例阈值，"
            "同样只作算例参数，不是机组保护定值。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        case_mode="sequence",
        provenance={
            "source_type": "队友评审草案改编（P04）",
            "origin": "2026 CIMC 初赛超压联锁题：跳闸后要能事后回答"
                      "'为什么跳'，线索位编码是赛场实现方式。",
            "adaptation": "把原草案的派生谓词 tripCause1/2/3 改为显式位掩码 + 滞环复位；"
                          "补充变送器失效优先、足迹保留两条边界。",
            "review": "人工审核（lym 11.2 复核后修订）：WORD 位宽与“足迹≠瞬间快照”"
                      "写进题面；补 4500/4499、4200/4201、outletCmd=50/outletFeedback=10、"
                      "fuelFlow=4.0/steamFlow=10.0 边界；补卡滞计数四种清零途径、"
                      "非法复位与“条件后满足但无新上升沿”；S4 加强为“有上升沿但许可不满足"
                      "也不得解锁”，并补 bit0~bit3 的位编码性质与足迹单调性。",
        },
    )

# ==========================================================================
# P05 self-hard-07 串级 PI 控制手自动无扰切换
# ==========================================================================

def p05_cascade_pi() -> Problem:
    variables = [
        V("mode", "INT", "0=手动 1=自动 2=串级（其它值为故障回退）"),
        V("resetBtn", "BOOL", "复位（上升沿回到初值）"),
        V("dt", "REAL", "本次扫描周期（秒）"),
        V("tempSP", "REAL", "温度设定值（℃）"),
        V("tempPV", "REAL", "温度测量值（℃）"),
        V("flowPV", "REAL", "流量测量值（t/h）"),
        V("manualFlowSP", "REAL", "手动流量设定值（t/h）"),
        V("manualValve", "REAL", "手动阀门开度取值（%）"),
        V("flowSP", "REAL", "流量设定值输出（t/h，限幅 0..50）", OUTD),
        V("valveCommand", "REAL", "阀门开度指令（%，限幅 0..100）", OUTD),
        V("fault", "BOOL", "故障（模式越界或 dt 越界）", OUTD),
        V("normalMode", "BOOL", "本拍处于正常运算（非复位/故障/切换/首次拍）", OUTD),
    ]

    def c(tc_id, mode, dt, tsp, tpv, fpv, msp, mv, reset, exp, note):
        return seq(tc_id,
                   {"mode": mode, "dt": dt, "tempSP": tsp, "tempPV": tpv,
                    "flowPV": fpv, "manualFlowSP": msp, "manualValve": mv,
                    "resetBtn": reset}, exp, note)

    cases = [
        c("q1", -1, 1.0, 100.0, 98.0, 20.0, 5.0, 20.0, False,
          {"flowSP": 5.0, "valveCommand": 20.0, "fault": True, "normalMode": False},
          "首次执行即 mode=-1：故障回退跟手操，accT=5-(100-98)=3、"
          "accF=20-2*(5-20)=50"),
        c("q2", 0, 1.0, 100.0, 98.0, 20.0, 5.0, 20.0, False,
          {"flowSP": 5.0, "valveCommand": 20.0, "fault": False, "normalMode": False},
          "mode 由 -1 切到 0：切换当拍预置积分器、输出保持手动值，不运算"),
        c("q3", 0, 1.0, 100.0, 98.0, 20.0, 5.0, 35.0, False,
          {"flowSP": 5.0, "valveCommand": 35.0, "fault": False, "normalMode": True},
          "手动正常运算：flowSP 跟 manualFlowSP=5、valveCommand 跟 manualValve=35"),
        c("q4", 1, 1.0, 100.0, 98.0, 10.0, 5.0, 35.0, False,
          {"flowSP": 5.0, "valveCommand": 35.0, "fault": False, "normalMode": False},
          "切到自动：当拍预置 accF=35-2*(5-10)=45，输出仍保持 35"),
        c("q5", 1, 1.0, 100.0, 98.0, 10.0, 5.0, 35.0, False,
          {"flowSP": 5.0, "valveCommand": 32.5, "fault": False, "normalMode": True},
          "自动正常运算：eF=5-10=-5，trial=45-2.5=42.5，valve=2*(-5)+42.5=32.5，"
          "accF=32.5+10=42.5"),
        c("q6", 1, 1.0, 100.0, 98.0, 10.0, 5.0, 35.0, False,
          {"flowSP": 5.0, "valveCommand": 30.0, "fault": False, "normalMode": True},
          "自动第 2 拍：trial=42.5-2.5=40，valve=-10+40=30，accF=40"),
        c("q7", 1, 1.0, 100.0, 98.0, 10.0, 10.0, 35.0, False,
          {"flowSP": 10.0, "valveCommand": 40.0, "fault": False, "normalMode": True},
          "自动模式下 manualFlowSP 改成 10：flowSP 立即跟 10（eF=0 → valve 不变）"),
        c("q8", 2, 1.0, 100.0, 98.0, 10.0, 10.0, 35.0, False,
          {"flowSP": 10.0, "valveCommand": 40.0, "fault": False, "normalMode": False},
          "切到串级：当拍不运算，flowSP/valveCommand 均保持上一拍（10/40）"),
        c("q9", 2, 1.0, 100.0, 98.0, 10.0, 10.0, 35.0, False,
          {"flowSP": 10.4, "valveCommand": 41.0, "fault": False, "normalMode": True},
          "串级正常运算：eT=2，外环 trial=8+0.4=8.4，flowSP=2+8.4=10.4；"
          "eF=0.4，内环 trial=40+0.2=40.2，valve=0.8+40.2=41"),
        c("q10", 2, 1.0, 100.0, 98.0, 10.0, 10.0, 35.0, False,
          {"flowSP": 10.8, "valveCommand": 42.2, "fault": False, "normalMode": True},
          "串级第 2 拍：外环 accT=8.4 → trial 8.8 → flowSP 10.8；内环 valve 42.2"),
        c("q11", 1, 1.0, 100.0, 98.0, 10.0, 10.0, 35.0, False,
          {"flowSP": 10.0, "valveCommand": 42.2, "fault": False, "normalMode": False},
          "串级切回自动：flowSP 跟 manualFlowSP=10，valveCommand 保持 42.2"),
        c("q12", 1, 1.0, 100.0, 98.0, 10.0, 10.0, 35.0, False,
          {"flowSP": 10.0, "valveCommand": 42.2, "fault": False, "normalMode": True},
          "自动正常运算：eF=0，valve 保持 42.2"),
        c("q13", 3, 1.0, 100.0, 98.0, 10.0, 10.0, 99.0, False,
          {"flowSP": 10.0, "valveCommand": 99.0, "fault": True, "normalMode": False},
          "mode=3 越界 → 故障回退：输出立即跟手操（允许阀位跳变）"),
        c("q14", 2, 1.0, 100.0, 98.0, 10.0, 10.0, 99.0, False,
          {"flowSP": 10.0, "valveCommand": 99.0, "fault": False, "normalMode": False},
          "故障恢复后切到串级：当拍预置积分器、输出保持 99"),
        c("q15", 2, 1.0, 100.0, 98.0, 10.0, 10.0, 99.0, False,
          {"flowSP": 10.4, "valveCommand": 100.0, "fault": False, "normalMode": True},
          "串级正常运算：内环输出 100.8 被上限 100 截断（accF 回算 99.2）"),
        c("q16", 2, 1.0, 100.0, 98.0, 20.0, 10.0, 99.0, False,
          {"flowSP": 10.8, "valveCommand": 76.2, "fault": False, "normalMode": True},
          "flowPV 升到 20：eF=-9.2，valve 从饱和 100 立刻回到 76.2（回算未积压）"),
        c("q17", 2, 1.0, 100.0, 98.0, 40.0, 10.0, 99.0, False,
          {"flowSP": 11.2, "valveCommand": 22.6, "fault": False, "normalMode": True},
          "flowPV=40：eF=-28.8，valve 22.6"),
        c("q18", 2, 1.0, 100.0, 98.0, 40.0, 10.0, 99.0, False,
          {"flowSP": 11.6, "valveCommand": 9.2, "fault": False, "normalMode": True},
          "串级继续：valve 9.2"),
        c("q19", 0, 1.0, 100.0, 98.0, 40.0, 10.0, 99.0, False,
          {"flowSP": 10.0, "valveCommand": 9.2, "fault": False, "normalMode": False},
          "串级→手动（连续切换第 1 拍）：flowSP 跟手操 10，valve 保持 9.2"),
        c("q20", 1, 1.0, 100.0, 98.0, 40.0, 10.0, 99.0, False,
          {"flowSP": 10.0, "valveCommand": 9.2, "fault": False, "normalMode": False},
          "手→自动（连续切换第 2 拍）：当拍仍不运算，输出保持"),
        c("q21", 2, 1.0, 100.0, 98.0, 40.0, 30.0, 99.0, False,
          {"flowSP": 10.0, "valveCommand": 9.2, "fault": False, "normalMode": False},
          "自动→串级（连续切换第 3 拍）：manualFlowSP=30 也不得被采用，"
          "flowSP 保持上一拍 10.0"),
        c("q22", 2, 1.0, 100.0, 98.0, 40.0, 10.0, 99.0, False,
          {"flowSP": 10.4, "valveCommand": 0.0, "fault": False, "normalMode": True},
          "串级正常运算：eF=-29.6，valve 算出 -4.8 被下限 0 截断"),
        c("q23", 1, 1.0, 100.0, 98.0, 20.0, 10.0, 50.0, True,
          {"flowSP": 10.0, "valveCommand": 50.0, "fault": False, "normalMode": False},
          "复位上升沿：回初值（跟 manualFlowSP=10 / manualValve=50），当拍不运算"),
        c("q24", 2, 1.0, 100.0, 98.0, 20.0, 10.0, 50.0, True,
          {"flowSP": 10.0, "valveCommand": 50.0, "fault": False, "normalMode": False},
          "复位按住不放 + 切模式：没有新上升沿不再复位，按切换处理，输出保持"),
        c("q25", 2, 1.0, 100.0, 98.0, 20.0, 10.0, 50.0, False,
          {"flowSP": 10.4, "valveCommand": 46.0, "fault": False, "normalMode": True},
          "松开复位后串级正常运算：valve 46"),
        c("q26", 2, 1.0, 100.0, 98.0, 20.0, 10.0, 20.0, True,
          {"flowSP": 10.0, "valveCommand": 20.0, "fault": False, "normalMode": False},
          "复位后松手再按：重新出现上升沿 → 再次回初值"),
        c("q27", 2, 10.0, 100.0, 98.0, 20.0, 10.0, 20.0, True,
          {"flowSP": 14.0, "valveCommand": 0.0, "fault": False, "normalMode": True},
          "复位按住 + dt=10.0（允许上限）：不重复复位，按串级运算，"
          "外环 8+0.2*2*10=12 → flowSP 14；内环 eF=-6 → valve 10-12=-2 截断 0"),
        c("q28", 2, 10.1, 100.0, 98.0, 20.0, 10.0, 20.0, False,
          {"flowSP": 10.0, "valveCommand": 20.0, "fault": True, "normalMode": False},
          "dt=10.1 > 10.0 → 时基异常故障：跟手操"),
        c("q29", 2, 0.0, 100.0, 98.0, 20.0, 10.0, 20.0, False,
          {"flowSP": 10.0, "valveCommand": 20.0, "fault": True, "normalMode": False},
          "dt=0 → 故障"),
        c("q30", 2, -1.0, 100.0, 98.0, 20.0, 10.0, 20.0, False,
          {"flowSP": 10.0, "valveCommand": 20.0, "fault": True, "normalMode": False},
          "dt=-1 → 故障（负时标不允许）"),
        c("q31", 1, 1.0, 100.0, 98.0, 20.0, 10.0, 20.0, False,
          {"flowSP": 10.0, "valveCommand": 20.0, "fault": False, "normalMode": False},
          "故障消失后切到自动：当拍预置积分器、输出保持"),
        c("q32", 1, 1.0, 100.0, 98.0, 20.0, 10.0, 20.0, False,
          {"flowSP": 10.0, "valveCommand": 15.0, "fault": False, "normalMode": True},
          "自动正常运算：eF=-10，trial=40-5=35，valve=-20+35=15"),
        c("q33", 1, 1.0, 100.0, 98.0, 20.0, 10.0, 20.0, False,
          {"flowSP": 10.0, "valveCommand": 10.0, "fault": False, "normalMode": True},
          "自动第 2 拍：valve 10"),
        c("q34", 1, 1.0, 100.0, 98.0, 0.0, 10.0, 20.0, False,
          {"flowSP": 10.0, "valveCommand": 55.0, "fault": False, "normalMode": True},
          "flowPV=0：eF=10，trial=30+5=35，valve=20+35=55"),
        c("q35", 1, 1.0, 100.0, 98.0, 0.0, 10.0, 20.0, False,
          {"flowSP": 10.0, "valveCommand": 60.0, "fault": False, "normalMode": True},
          "自动第 2 拍：valve 60"),
        c("q36", 2, 1.0, 100.0, 98.0, 0.0, 10.0, 20.0, False,
          {"flowSP": 10.0, "valveCommand": 60.0, "fault": False, "normalMode": False},
          "切到串级：valve 保持 60，积分器按当前偏差重算"),
        c("q37", 2, 1.0, 30.0, 100.0, 10.0, 10.0, 20.0, False,
          {"flowSP": 0.0, "valveCommand": 15.0, "fault": False, "normalMode": True},
          "外环下限：eT=-70，trial=8-14=-6，flowSP=-76 截断 0（accT 回算 70）"),
        c("q38", 2, 1.0, 30.0, 100.0, 10.0, 10.0, 20.0, False,
          {"flowSP": 0.0, "valveCommand": 10.0, "fault": False, "normalMode": True},
          "继续：valve 10"),
        c("q39", 2, 1.0, 400.0, 100.0, 10.0, 10.0, 20.0, False,
          {"flowSP": 50.0, "valveCommand": 100.0, "fault": False, "normalMode": True},
          "外环上限：eT=300，flowSP 430 截断 50；内环 eF=40 → valve 130 截断 100"),
        c("q40", 2, 1.0, 100.0, 80.0, 10.0, 10.0, 20.0, False,
          {"flowSP": 0.0, "valveCommand": 0.0, "fault": False, "normalMode": True},
          "上下限解除：外环 8→accT=-20，flowSP 截断 0；内环 accF=20，valve 截断 0"),
    ]
    specs = [
        Spec("S1", "流量设定值始终在 0..50 t/h 之间。",
             "G((flowSP >= 0.0) & (flowSP <= 50.0))", "safety"),
        Spec("S2", "阀门指令始终在 0..100 % 之间。",
             "G((valveCommand >= 0.0) & (valveCommand <= 100.0))", "safety"),
        Spec("S3", "故障周期必须立即回退到手动：跟手操值且本拍非正常运算。",
             "G(fault -> ((flowSP = manualFlowSP) & (valveCommand = manualValve) & "
             "!normalMode))", "safety"),
        Spec("S4", "复位上升沿必须让回路回到初值：跟手操值且本拍非正常运算。",
             "G(rising(resetBtn) -> ((flowSP = manualFlowSP) & "
             "(valveCommand = manualValve) & !normalMode))", "safety"),
        Spec("S5", "手动正常运算周期两个输出分别跟随手动给定。",
             "G((normalMode & (mode = 0)) -> ((flowSP = manualFlowSP) & "
             "(valveCommand = manualValve)))", "safety"),
        Spec("S6", "自动正常运算周期流量设定跟随 manualFlowSP。",
             "G((normalMode & (mode = 1)) -> (flowSP = manualFlowSP))", "safety"),
        Spec("S7", "由正常运算切到非串级模式时，切换当拍流量设定取手动值（预置型切换）。",
             "G((prev(normalMode) & (mode <> prev(mode)) & !fault & !rising(resetBtn) & "
             "(mode <> 2)) -> (flowSP = manualFlowSP))", "sequencing"),
        Spec("S8", "由正常运算切到串级模式时，切换当拍两个输出都必须保持上一拍值（不跳变）。",
             "G((prev(normalMode) & (mode <> prev(mode)) & !fault & !rising(resetBtn) & "
             "(mode = 2)) -> ((flowSP = prev(flowSP)) & "
             "(valveCommand = prev(valveCommand))))", "sequencing"),
        Spec("S9", "串级/自动 PI 的积分预置、抗积分饱和回算、dt 校验与手动保持的完整行为。",
             "", "data", verified_by="simulation"),
    ]
    return Problem(
        pid="self-hard-07",
        source="selfmade",
        difficulty=Difficulty.HARD,
        title="串级 PI 温控回路的手/自动无扰切换（bumpless transfer）",
        requirements=(
            "写一个功能块 FB，实现**串级 PI 控制回路**的手/自动无扰切换。\n"
            "1. 串级结构：外环以温度偏差驱动流量设定，内环以流量偏差驱动阀门开度；\n"
            "2. 模式：0=手动（操作员直接给定流量设定与阀门开度，两者都跟随手动值）；"
            "1=自动（手动给定流量设定 manualFlowSP，内环 PI 自动算阀门）；"
            "2=串级（温度环 PI 算流量设定，流量环 PI 算阀门）；\n"
            "3. 每个扫描周期只执行一次，dt 为本次周期时长（秒）；控制器系数按**秒**计算："
            "外环 KiT=0.2/s、内环 KiF=0.5/s；温度偏差 eT=tempSP-tempPV（℃），"
            "流量偏差 eF=flowSP-flowPV（t/h），阀门开度单位 %，因此积分项 accT 的单位是"
            "t/h、accF 的单位是 %，增益 1.0 与 2.0 分别对应 ℃→t/h 与 t/h→% 的折算：\n"
            "   外环 trial = accT + 0.2*eT*dt；flowSP = 1.0*eT + trial；限幅 0..50"
            "（t/h）；accT = flowSP - 1.0*eT；\n"
            "   内环 trial = accF + 0.5*eF*dt；valveCommand = 2.0*eF + trial；"
            "限幅 0..100（%）；accF = valveCommand - 2.0*eF；\n"
            "   抗积分饱和用**回算**：acc 取限幅后的实际输出反算，因此限幅期间积分不会"
            "越积越多、解除饱和后立即恢复；\n"
            "4. 无扰切换（bumpless）：任何模式切换都在**切换当拍**预置积分器，把 "
            "accT/accF 反算成“上一拍输出值”，该拍输出保持不变（不跳变）；只有自动/"
            "串级**正常运算**的周期才允许输出变化；\n"
            "5. 复位 resetBtn 上升沿：整个回路回到初值——预置积分器、输出跟手动值、"
            "当拍不运算；按住不放不重复动作；\n"
            "6. 故障安全：mode 不在 0/1/2，或 dt<=0.0（时标丢失），或 dt>10.0"
            "（超过 10 s 的扫描周期视为时基异常）→ fault 置位，输出**立即**跟手动值、"
            "不积分，并预置积分器；故障期间允许阀位跳变（安全优先，与“无扰切换”区分）；\n"
            "7. 复位/故障优先于正常运算：同一拍既有复位上升沿又有故障时，按复位处理"
            "（两者输出相同，均跟手动值）；\n"
            "8. normalMode 表示“本拍处于正常运算”，即既不在复位拍也不在故障、也不在"
            "模式切换/首次执行拍；\n"
            "9. 模式可以任意跳转（不要求 0→1→2 依次投入；直接 0→2 合法）；但工程上一般"
            "建议先投入内环（1）再投入外环（2），这样温度环 PI 的积分器在切换时已有较"
            "接近的初值、可减少切换瞬态——这是操作建议，不是本块强制的算法约束。\n"
            "扫描周期与单位约定：dt 由调用方每周期给出（秒）；模块内部不做时基换算，"
            "因此同一份参数在 dt=0.1 s 或 1 s 的扫描下控制效果不同——这是本算例的简化；"
            "实际工程应把 Ki 换成“每周期”形式或显式按扫描周期折算。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        case_mode="sequence",
        provenance={
            "source_type": "队友评审草案改编（P05）",
            "origin": "2026 CIMC 决赛串级温控题：上位机可切手/自动/串级，切换不允许"
                      "扰动阀门。",
            "adaptation": "把原草案的单环 PI 扩成温度-流量串级；补充复位、故障安全、"
                          "抗积分饱和与模式任意跳转的边界。",
            "review": "人工审核（lym 11.2 复核后修订）：q13 注释补积分更新步骤；"
                      "q5 手操值改 30 以验证串级切换当拍不偷用 manualFlowSP；说明"
                      "自动→手动是预置型切换（当拍保持、允许接管后突变）；补充 PI "
                      "系数量纲与按秒计算；明确故障回退允许阀位跳变（安全优先）且"
                      "不要求 0→1→2 依次投入；新增复位、连续两拍切换、dt 边界、"
                      "上下限幅与解除饱和的用例，并把切换性质写成 S7/S8 两条规约。",
        },
    )

BUILDERS = [p01_flame_o2, p02_steam_profit, p03_fuzzy_temp, p04_overpressure,
            p05_cascade_pi]


def main() -> None:
    # 自检函数在 selfmade_build.py 里，按文件位置找同目录，避免依赖 cwd/入口方式
    here = str(Path(__file__).resolve().parent)
    if here not in sys.path:
        sys.path.insert(0, here)
    from selfmade_build import self_check

    OUT.mkdir(parents=True, exist_ok=True)
    failed = 0
    for build in BUILDERS:
        p = build()
        errs = self_check(p)
        if errs:
            failed += 1
            print(f"{p.pid}: 自检未通过")
            for e in errs:
                print("   ", e)
            continue
        p.save(OUT / f"{p.pid}.json")
        print(f"{p.pid:16s} {p.difficulty.value:6s} vars={len(p.variables):2d} "
              f"specs={len(p.specs)} cases={len(p.test_cases):2d}  {p.title}")
    if failed:
        raise SystemExit(f"{failed} 道题自检未通过，已中止（未写盘）")


if __name__ == "__main__":
    main()
