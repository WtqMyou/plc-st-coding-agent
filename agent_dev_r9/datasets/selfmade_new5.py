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
        V("baseAir", "REAL", "主风门基础开度给定（%）"),
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
            {"tripLatched": True, "fuelPermit": False, "airCommand": 0.0},
            "跳闸自保持：火焰恢复也不自动复位"),
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
    ]
    specs = [
        Spec("S1", "运行中失去火焰时，**同一周期**就必须跳闸（不得延迟一拍）。",
             "G((runRequest & !flameOK) -> tripLatched)", "safety"),
        Spec("S2", "跳闸一旦置位就自保持，只能由复位上升沿清除。",
             "G((prev(tripLatched) & !rising(resetBtn) & (flameOK | runRequest)) -> tripLatched)",
             "safety"),
        Spec("S3", "跳闸状态下绝不允许燃料许可。",
             "G(tripLatched -> !fuelPermit)", "safety"),
        Spec("S4", "无运行请求时不得给出燃料许可。",
             "G(fuelPermit -> runRequest)", "safety"),
        Spec("S5", "无燃料许可时风门命令必须归零（防止停机后残留开度）。",
             "G(!fuelPermit -> airCommand = 0.0)", "safety"),
        Spec("S6", "风门命令恒在 0..100 之间。",
             "G((airCommand >= 0.0) & (airCommand <= 100.0))", "safety"),
        Spec("S7", "氧量修正偏置恒在 ±10 之间。",
             "G((airTrim >= -10.0) & (airTrim <= 10.0))", "safety"),
        Spec("S8", "氧量分析仪故障当拍必须切除修正。",
             "G(o2Fault -> (trimEnable = FALSE & airTrim = 0.0))", "safety"),
        Spec("S9", "故障判据：数据无效或超出 0..21 量程。",
             "G(o2Fault <-> (!o2Valid | o2PV < 0.0 | o2PV > 21.0))", "safety"),
        Spec("S10", "修正系数与钳位后的合成值。", "",
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
            "2. tripLatched 自保持，只有在 runRequest=FALSE 且 flameOK=FALSE 的前提下，"
            "resetBtn 的**上升沿**才能清除；\n"
            "3. fuelPermit = runRequest AND flameOK AND NOT tripLatched；\n"
            "4. 氧量修正：trimEnable = fuelPermit AND NOT o2Fault；"
            "trimmer = 2.0 * (2.0 - o2PV)，并钳位到 [-10, +10]；"
            "trimEnable=FALSE 时 airTrim 必须为 0.0；\n"
            "5. o2Fault = NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0"
            "（分析仪故障只切除修正，**不得**切除燃料）；\n"
            "6. airCommand = baseAir + airTrim，钳位到 [0, 100]；"
            "fuelPermit=FALSE 时 airCommand 必须为 0.0。"
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
            "【边界】dt=0 判数据故障：本拍不累计，不得除零也不得写坏累计值"),
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
            {"dataFault": True, "fuelTon": 0.001},
            "【边界】dt=11 超上限 → 故障，不累计"),
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
            {"dataFault": True, "fuelTon": 0.013},
            "【边界】燃料 6.1 超量程 → 故障"),
    ]
    specs = [
        Spec("S1", "合格判据：温度 447..453 ℃ 且 压力 3750..3850 kPa（闭区间）。",
             "G(qualified <-> (steamTemp >= 447.0 & steamTemp <= 453.0 "
             "& steamPressure >= 3750.0 & steamPressure <= 3850.0))", "safety"),
        Spec("S2", "累计产量与累计燃料消耗永远非负。",
             "G((qualifiedTon >= 0.0) & (fuelTon >= 0.0))", "safety"),
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
        Spec("S7", "收入与成本随累计量单调（不得出现负收入）。",
             "G(revenue >= 0.0 & cost >= 0.0)", "safety"),
        Spec("S8", "累计量按 flow*dt/1000 递推，收入=产量*280，成本=燃料*1500。", "",
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
            "[3750.0, 3850.0]（**闭区间**，端点合格）；\n"
            "2. 本周期合格且 enable=TRUE 且无数据故障时，"
            "qualifiedTon += steamFlow * dt / 1000.0（kg/s × s ÷ 1000 → t）；"
            "无论是否合格，只要 enable 且无故障，fuelTon += fuelFlow * dt / 1000.0；\n"
            "3. 数据故障判据：dt <= 0.0 或 dt > 10.0 或 steamFlow 不在 [0,90] "
            "或 fuelFlow 不在 [0,6]；故障拍**不累计**，累计值保持不变；\n"
            "4. resetBtn 上升沿：两个累计量清零，且**当拍不再累计**；\n"
            "5. revenue = qualifiedTon * 280.0，cost = fuelTon * 1500.0，"
            "netProfit = revenue - cost，三者每拍都要更新（即使不累计）。\n"
            "6. 所有累计量必须是非负的；enable=FALSE 时只更新判定位，不改累计量。"
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
            "首拍无历史：de=0，x=1.0/y=0 → 只踩 Z×P 规则，修正 +20"),
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
            "三邻域同时激活：x=0.2/y=0.5 → 权重 Z×P(.4)、P×Z(.2)、P×P(.3) 与 P×Z 归一分母1 → 修正 (+4+2+3)/1 = 9.0"),
        seq("q5", {"enable": True, "resetBtn": False, "sensorValid": False,
                   "setpoint": 100.0, "temperature": 98.0, "dt": 1.0, "bias": 50.0},
            {"fault": True, "power": 0.0, "correction": 0.0},
            "传感器故障：功率与修正都归零，并清除历史误差"),
        seq("q6", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 100.0, "dt": 1.0, "bias": 50.0},
            {"fault": False, "correction": 0.0, "power": 50.0},
            "故障恢复首拍：历史已清除，按 de=0 处理，只出基础输出"),
        seq("q7", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 120.0},
            {"correction": 30.0, "power": 100.0},
            "【边界】120+30=150 越界 → power 钳位 100，但 correction 仍报 30"),
        seq("q8", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 0.0},
            {"correction": 20.0, "power": 20.0},
            "下界侧：0+20=20 在范围内，不触发钳位"),
        seq("q9", {"enable": True, "resetBtn": False, "sensorValid": True,
                   "setpoint": 100.0, "temperature": 90.0, "dt": 0.0, "bias": 50.0},
            {"fault": True, "power": 0.0, "correction": 0.0},
            "【边界】dt=0 → 故障（既不能除零，也不允许按 0 周期积分）"),
        seq("q10", {"enable": False, "resetBtn": False, "sensorValid": True,
                    "setpoint": 100.0, "temperature": 90.0, "dt": 1.0, "bias": 50.0},
            {"fault": False, "power": 0.0, "correction": 0.0},
            "未投入自动：输出归零"),
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
        Spec("S6", "功率 = 基础输出 + 修正后再钳位。", "",
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
            "2. x = clamp(e / 10.0, -1, 1)，y = clamp(de / 2.0, -1, 1)；\n"
            "3. 隶属度：μN(z)=max(-z,0)、μZ(z)=1-|z|、μP(z)=max(z,0)；\n"
            "4. 九条规则的单点输出：N×N=-30、N×Z=-20、N×P=-10、Z×N=-10、Z×Z=0、"
            "Z×P=10、P×N=10、P×Z=20、P×P=30；"
            "correction = Σ(w·c)/Σw（重心法），Σw=0 时 correction=0；\n"
            "5. power = clamp(bias + correction, 0, 100)，**correction 不钳位**；\n"
            "6. fault = NOT sensorValid OR dt <= 0.0 OR dt > 10.0；"
            "fault、enable=FALSE 或 resetBtn 上升沿时：power=0、correction=0，"
            "并清除历史（ePrev=0、历史标志=FALSE）。"
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
        V("fuelFlow", "REAL", "燃料流量（kg/s）"),
        V("steamFlow", "REAL", "蒸汽流量（kg/s）"),
        V("outletCmd", "INT", "减温减压阀开度命令（%）"),
        V("outletFeedback", "INT", "减温减压阀开度反馈（%）"),
        V("resetBtn", "BOOL", "复位按钮（上升沿有效）"),
        V("tripLatched", "BOOL", "超压跳闸自保持", OUTD),
        V("fuelPermit", "BOOL", "燃料许可", OUTD),
        V("currentCauseMask", "WORD", "本周期诊断线索位掩码", OUTD),
        V("latchedCauseMask", "WORD", "跳闸时的线索累积掩码", OUTD),
        V("diagnosticActive", "BOOL", "存在有效诊断线索", OUTD),
    ]
    cases = [
        seq("q1", {"runRequest": False, "pressure": 4000.0, "pressureValid": True,
                   "fuelFlow": 1.0, "steamFlow": 20.0, "outletCmd": 0,
                   "outletFeedback": 0, "resetBtn": False},
            {"tripLatched": False, "fuelPermit": False, "currentCauseMask": 0,
             "latchedCauseMask": 0, "diagnosticActive": False},
            "停机初始：无跳闸、无线索"),
        seq("q2", {"runRequest": True, "pressure": 4200.0, "pressureValid": True,
                   "fuelFlow": 2.0, "steamFlow": 20.0, "outletCmd": 60,
                   "outletFeedback": 60, "resetBtn": False},
            {"tripLatched": False, "fuelPermit": True, "currentCauseMask": 0},
            "压力 4200 未达 4500：允许燃料，无线索"),
        seq("q3", {"runRequest": True, "pressure": 4600.0, "pressureValid": True,
                   "fuelFlow": 2.0, "steamFlow": 20.0, "outletCmd": 60,
                   "outletFeedback": 60, "resetBtn": False},
            {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 8,
             "latchedCauseMask": 8, "diagnosticActive": True},
            "超压但阀位正常、燃烧正常 → 线索=8（未定位）"),
        seq("q4", {"runRequest": True, "pressure": 4600.0, "pressureValid": True,
                   "fuelFlow": 2.0, "steamFlow": 20.0, "outletCmd": 80,
                   "outletFeedback": 0, "resetBtn": False},
            {"tripLatched": True, "currentCauseMask": 8, "latchedCauseMask": 8},
            "阀卡滞第 1 拍（计数 1，未达 3 拍判据）仍只报 8"),
        seq("q5", {"runRequest": True, "pressure": 4600.0, "pressureValid": True,
                   "fuelFlow": 4.5, "steamFlow": 5.0, "outletCmd": 80,
                   "outletFeedback": 0, "resetBtn": False},
            {"currentCauseMask": 4, "latchedCauseMask": 12},
            "阀计数 2 + 燃烧过剩 → 位2 已置（8|4=12）"),
        seq("q6", {"runRequest": True, "pressure": 4600.0, "pressureValid": True,
                   "fuelFlow": 4.5, "steamFlow": 5.0, "outletCmd": 80,
                   "outletFeedback": 0, "resetBtn": False},
            {"currentCauseMask": 6, "latchedCauseMask": 14},
            "阀计数达 3 → 位1 置；与位2 合并得 6（14=8|4|2）"),
        seq("q7", {"runRequest": False, "pressure": 4000.0, "pressureValid": True,
                   "fuelFlow": 0.0, "steamFlow": 0.0, "outletCmd": 0,
                   "outletFeedback": 0, "resetBtn": False},
            {"tripLatched": True, "fuelPermit": False, "currentCauseMask": 0,
             "latchedCauseMask": 14, "diagnosticActive": False},
            "停机后本拍无线索，但**已累积**的足迹必须保留（供事后诊断）"),
        seq("q8", {"runRequest": False, "pressure": 4000.0, "pressureValid": True,
                   "fuelFlow": 0.0, "steamFlow": 0.0, "outletCmd": 0,
                   "outletFeedback": 0, "resetBtn": True},
            {"tripLatched": False, "currentCauseMask": 0, "latchedCauseMask": 0},
            "复位：runRequest=FALSE、压力已回落到 <=4200 → 跳闸与足迹一起清"),
        seq("q9", {"runRequest": True, "pressure": 4600.0, "pressureValid": True,
                   "fuelFlow": 4.5, "steamFlow": 5.0, "outletCmd": 0,
                   "outletFeedback": 0, "resetBtn": False},
            {"tripLatched": True, "currentCauseMask": 4, "latchedCauseMask": 4},
            "阀命令未达 50 → 不计卡滞；只剩燃烧过剩线索"),
        seq("q10", {"runRequest": True, "pressure": 4600.0, "pressureValid": False,
                    "fuelFlow": 4.5, "steamFlow": 5.0, "outletCmd": 90,
                    "outletFeedback": 0, "resetBtn": False},
            {"tripLatched": True, "currentCauseMask": 1, "latchedCauseMask": 5},
            "变送器失效：线索=1（优先于压力判据），并入累积 5"),
    ]
    specs = [
        Spec("S1", "压力变送器失效且仍在运行时，必须当拍跳闸并切除燃料。",
             "G((runRequest & !pressureValid) -> (tripLatched & !fuelPermit))", "safety"),
        Spec("S2", "母管压力达到 4500 kPa（数据有效）时必须当拍跳闸。",
             "G((runRequest & pressureValid & pressure >= 4500.0) -> tripLatched)",
             "safety"),
        Spec("S3", "跳闸状态下绝不允许燃料许可。",
             "G(tripLatched -> !fuelPermit)", "safety"),
        Spec("S4", "跳闸自保持，非复位上升沿不得自动清除。",
             "G((prev(tripLatched) & !rising(resetBtn)) -> tripLatched)", "safety"),
        Spec("S5", "无运行请求时本周期线索掩码必须为 0。",
             "G(!runRequest -> currentCauseMask = 0)", "safety"),
        Spec("S6", "压力未越限且数据有效时不产生线索。",
             "G((runRequest & pressureValid & pressure < 4500.0) -> "
             "currentCauseMask = 0)", "safety"),
        Spec("S7", "诊断有效位与线索掩码一致。",
             "G(diagnosticActive <-> currentCauseMask <> 0)", "safety"),
        Spec("S8", "复位条件满足时跳闸必须清除。",
             "G((rising(resetBtn) & !runRequest & pressureValid & pressure <= 4200.0) "
             "-> !tripLatched)", "safety"),
        Spec("S9", "诊断线索的位含义与累积方式（按位或并入足迹）。", "",
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
            "pressureValid 且 pressure <= 4200.0（滞环，防抖动）；\n"
            "4. 线索位（currentCauseMask，WORD，本拍重新计算）："
            "bit0=1 变送器失效；bit1=2 减温减压阀卡滞（outletCmd>=50 且 "
            "outletFeedback<=10 连续 **3 拍及以上**，每拍须同时满足运行、压力有效且压力>=4500；任一中断清零）；bit2=4 燃烧过剩"
            "（fuelFlow >= 4.0 且 steamFlow <= 10.0）；"
            "若超压但以上线索都不成立，置 bit3=8（未定位）；"
            "NOT runRequest 时线索为 0；\n"
            "5. latchedCauseMask：tripLatched 为 TRUE 时把 currentCauseMask **按位或**并入"
            "（32 位字，不会溢出），复位时清零；\n"
            "6. fuelPermit = runRequest AND NOT tripLatched；"
            "diagnosticActive = (currentCauseMask <> 0)。"
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
            "review": "人工审核：位掩码用十进制断言（2/4/6/8/12/14/5）；"
                      "阀卡滞需连续 3 拍，中断即清零；无外部依赖。",
        },
    )


# ==========================================================================
# P05 self-hard-07 串级 PI 控制手自动无扰切换
# ==========================================================================

def p05_cascade_pi() -> Problem:
    variables = [
        V("mode", "INT", "0=手动 1=外环手动/内环自动 2=串级全自动"),
        V("resetBtn", "BOOL", "复位（上升沿）"),
        V("dt", "REAL", "本周期时长（s），合法 0 < dt <= 10"),
        V("tempSP", "REAL", "温度设定（℃）"),
        V("tempPV", "REAL", "温度测量（℃）"),
        V("flowPV", "REAL", "流量测量（t/h）"),
        V("manualFlowSP", "REAL", "流量设定手操值（t/h）"),
        V("manualValve", "REAL", "阀位手操值（%）"),
        V("flowSP", "REAL", "流量设定输出（t/h），钳位 0..50", OUTD),
        V("valveCommand", "REAL", "阀位命令（%），钳位 0..100", OUTD),
        V("fault", "BOOL", "模式或参数非法", OUTD),
        V("normalMode", "BOOL", "本拍按正常 PI 规则运算（非初始化/切换拍）", OUTD),
    ]
    cases = [
        seq("q1", {"mode": 0, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                   "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                   "manualValve": 40.0},
            {"fault": False, "flowSP": 10.0, "valveCommand": 40.0,
             "normalMode": False},
            "初始化拍：跟踪手操值，并把积分项预置成无扰初值"),
        seq("q2", {"mode": 0, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                   "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                   "manualValve": 40.0},
            {"flowSP": 10.0, "valveCommand": 40.0, "normalMode": True},
            "手动稳定拍：直接跟手操值，积分项持续跟踪"),
        seq("q3", {"mode": 1, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                   "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                   "manualValve": 40.0},
            {"flowSP": 10.0, "valveCommand": 40.0, "normalMode": False},
            "切到模式 1 的当拍：**不做积分**，阀位保持上一拍 40"),
        seq("q4", {"mode": 1, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                   "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                   "manualValve": 40.0},
            {"flowSP": 10.0, "valveCommand": 40.0, "normalMode": True},
            "模式 1 正常拍：eF=0 → 阀位不变"),
        seq("q5", {"mode": 2, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                   "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                   "manualValve": 40.0},
            {"flowSP": 10.0, "valveCommand": 40.0, "normalMode": False},
            "切到串级：流量设定必须**保持**上一拍值（不得跳到手操值）"),
        seq("q6", {"mode": 2, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                   "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                   "manualValve": 40.0},
            {"flowSP": 12.0, "valveCommand": 45.0, "normalMode": True},
            "串级第一正常拍：外环 eT=10 → flowSP=12，内环出 45"),
        seq("q7", {"mode": 2, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                   "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                   "manualValve": 40.0},
            {"flowSP": 14.0, "valveCommand": 51.0, "normalMode": True},
            "串级第二拍：积分继续累积 → 14 / 51"),
        seq("q8", {"mode": 0, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                   "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                   "manualValve": 20.0},
            {"flowSP": 10.0, "valveCommand": 51.0, "normalMode": False},
            "切回手动当拍：阀位保持 51（不跟手操 20），避免突跳"),
        seq("q9", {"mode": 0, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                   "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                   "manualValve": 20.0},
            {"flowSP": 10.0, "valveCommand": 20.0, "normalMode": True},
            "手动正常拍：跟手操 20，并把积分项重新预置成 20"),
        seq("q10", {"mode": 1, "resetBtn": False, "dt": 0.0, "tempSP": 100.0,
                    "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                    "manualValve": 30.0},
            {"fault": True, "flowSP": 10.0, "valveCommand": 30.0,
             "normalMode": False},
            "【边界】dt=0 → 故障，退回无扰跟踪并置 normalMode=FALSE"),
        seq("q11", {"mode": 3, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                    "tempPV": 90.0, "flowPV": 10.0, "manualFlowSP": 10.0,
                    "manualValve": 30.0},
            {"fault": True, "valveCommand": 30.0, "normalMode": False},
            "【边界】mode=3 非法 → 故障；不得按未知模式继续积分"),
        seq("q12", {"mode": 1, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                    "tempPV": 90.0, "flowPV": 20.0, "manualFlowSP": 10.0,
                    "manualValve": 30.0},
            {"fault": False, "flowSP": 10.0, "valveCommand": 30.0,
             "normalMode": False},
            "从非法模式恢复：仍按切换拍处理，阀位保持"),
        seq("q13", {"mode": 1, "resetBtn": False, "dt": 1.0, "tempSP": 100.0,
                    "tempPV": 90.0, "flowPV": 20.0, "manualFlowSP": 10.0,
                    "manualValve": 30.0},
            {"flowSP": 10.0, "valveCommand": 25.0, "normalMode": True},
            "模式 1 正常拍：eF=10-20=-10，iF=50（q12 预置）→ 阀位 clamp(2*(-10)+50)=25"),
    ]
    specs = [
        Spec("S1", "流量设定输出恒在 0..50 t/h 之间。",
             "G((flowSP >= 0.0) & (flowSP <= 50.0))", "safety"),
        Spec("S2", "阀位命令恒在 0..100 % 之间。",
             "G((valveCommand >= 0.0) & (valveCommand <= 100.0))", "safety"),
        Spec("S3", "模式切换的当拍阀位命令必须保持上一拍（无扰切换的核心）。",
             "G((prev(normalMode) & !normalMode & !rising(resetBtn) & !fault) -> "
             "valveCommand = prev(valveCommand))", "safety"),
        Spec("S4", "切入串级模式的当拍，流量设定必须保持上一拍值。",
             "G((prev(normalMode) & !normalMode & mode = 2 & !rising(resetBtn) & !fault) "
             "-> flowSP = prev(flowSP))", "safety"),
        Spec("S5", "故障拍退回无扰跟踪：流量设定跟手操、阀位跟手操。",
             "G(fault -> (flowSP = manualFlowSP & valveCommand = manualValve))", "safety"),
        Spec("S6", "正常运算拍必须处于合法模式且无故障。",
             "G(normalMode -> (!fault & mode >= 0 & mode <= 2))", "safety"),
        Spec("S7", "积分项递推与无扰预置（内环/外环）。", "",
             "data", verified_by="simulation"),
    ]
    return Problem(
        pid="self-hard-07",
        source="selfmade",
        difficulty=Difficulty.HARD,
        title="串级 PI 手自动无扰切换（积分预置 + 切换拍保持）",
        requirements=(
            "写一个功能块 FB，实现温度-流量串级 PI 控制的三模式无扰切换。\n"
            "控制要求：\n"
            "1. mode：0=手动、1=外环手动/内环自动、2=串级全自动；"
            "mode 不在 0..2、dt<=0 或 dt>10 判 fault；\n"
            "2. 初始化、复位上升沿、fault 三者的当拍：flowSP = manualFlowSP、"
            "valveCommand = manualValve，并把积分项预置为无扰值："
            "iT = flowSP - KpT*(tempSP-tempPV)，iF = valveCommand - KpF*(flowSP-flowPV)"
            "（KpT=1.0，KpF=2.0）；\n"
            "3. **模式切换的当拍不做积分**：阀位保持上一拍；切到 mode=2 时 "
            "flowSP 也保持上一拍，切到其它模式时 flowSP 跟 manualFlowSP；"
            "切换拍同时按上面公式重算 iT、iF；\n"
            "4. 正常运算拍（normalMode=TRUE）：\n"
            "   mode=0：flowSP=manualFlowSP、valveCommand=manualValve，重算 iT、iF；\n"
            "   mode=1：flowSP=manualFlowSP、iT 按公式跟踪；"
            "eF=flowSP-flowPV，iF += KiF*eF*dt（KiF=0.5），"
            "valveCommand=clamp(KpF*eF+iF,0,100)，随后 iF=valveCommand-KpF*eF；\n"
            "   mode=2：eT=tempSP-tempPV，iT += KiT*eT*dt（KiT=0.2），"
            "flowSP=clamp(KpT*eT+iT,0,50)，iT=flowSP-KpT*eT；再按 mode=1 的公式算内环；\n"
            "5. 模式切换的识别：非初始化拍比较 mode 与内部上一模式；即使连续两拍切换也必须识别；"
            "初始化记录当前 mode；下一合法非复位拍 mode 未变则正常运算（与 q2 一致），mode 变化则切换保持；\n"
            "6. normalMode 输出：本拍按正常 PI 规则运算则为 TRUE，"
            "初始化/切换/故障拍为 FALSE。调用方保证 manualFlowSP 在 [0,50]、manualValve 在 [0,100]；输入均为有限数。"
        ),
        variables=variables,
        specs=specs,
        test_cases=cases,
        case_mode="sequence",
        provenance={
            "source_type": "队友评审草案改编（P05）",
            "origin": "串级控制在流程行业极常见，手自动无扰切换是赛场与工程都要求的动作；"
                      "积分预置写错会造成阀位突跳。",
            "adaptation": "原草案接口只有 3 个输出，无法表达'切换拍'这一时序性质；"
                          "新增 normalMode 输出（本拍是否正常运算），"
                          "使 S3/S4 两条无扰切换性质可被 LTL 判定。",
            "review": "人工审核：Kp/Ki 均为给定常数；切换拍与正常拍严格分离；"
                      "钳位在积分重算之前进行，保证 iF 与阀位一致。",
        },
    )


BUILDERS = [p01_flame_o2, p02_steam_profit, p03_fuzzy_temp, p04_overpressure,
            p05_cascade_pi]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for build in BUILDERS:
        p = build()
        p.save(OUT / f"{p.pid}.json")
        print(f"{p.pid:16s} {p.difficulty.value:6s} vars={len(p.variables):2d} "
              f"specs={len(p.specs)} cases={len(p.test_cases):2d}  {p.title}")


if __name__ == "__main__":
    main()
