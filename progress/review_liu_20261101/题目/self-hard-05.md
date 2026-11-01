# self-hard-05：燃烧状态与氧量修正联锁（熄火跳闸 + 分析仪故障降级）

状态：待人工复核；指定负责人刘晏铭。

## 建议核对

- 熄火同拍跳闸、燃料许可与风量输出的关系是否明确？
- 氧量分析仪故障仅切除修正的设定是否适合本题边界？
- 复位上升沿及其前置条件、修正和风量的限幅是否合理？

## 题目与平台适配要求

写一个功能块 FB，实现燃烧器的火焰联锁与烟气氧量修正。
控制要求：
1. 运行请求 runRequest 为 TRUE 且火焰探测器 flameOK 为 FALSE 时，**当拍**置位熄火跳闸 tripLatched，并切断燃料许可；
2. tripLatched 自保持，只有在 runRequest=FALSE 且 flameOK=FALSE 的前提下，resetBtn 的**上升沿**才能清除；
3. fuelPermit = runRequest AND flameOK AND NOT tripLatched；
4. 氧量修正：trimEnable = fuelPermit AND NOT o2Fault；trimmer = 2.0 * (2.0 - o2PV)，并钳位到 [-10, +10]；trimEnable=FALSE 时 airTrim 必须为 0.0；
5. o2Fault = NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0（分析仪故障只切除修正，**不得**切除燃料）；
6. airCommand = baseAir + airTrim，钳位到 [0, 100]；fuelPermit=FALSE 时 airCommand 必须为 0.0。

## 接口

|变量|方向|类型|说明|
|---|---|---|---|
|runRequest|输入|BOOL|燃烧运行请求|
|flameOK|输入|BOOL|火焰探测器反馈（TRUE=检测到火焰）|
|o2Valid|输入|BOOL|氧量分析仪数据有效|
|o2PV|输入|REAL|烟气含氧量测量值（%）|
|baseAir|输入|REAL|主风门基础开度给定（%）|
|resetBtn|输入|BOOL|复位按钮（上升沿有效）|
|fuelPermit|输出|BOOL|燃料允许（联锁输出）|
|trimEnable|输出|BOOL|氧量修正投入（无故障才为 TRUE）|
|airTrim|输出|REAL|氧量修正偏置（%），钳位 ±10|
|airCommand|输出|REAL|风门开度命令（%），钳位 0..100|
|tripLatched|输出|BOOL|熄火跳闸自保持|
|o2Fault|输出|BOOL|氧量分析仪故障（无效或越界）|

## 性质说明

- S1：运行中失去火焰时，**同一周期**就必须跳闸（不得延迟一拍）。（已有 LTL 公式；实际结论以检查记录为准）
- S2：跳闸一旦置位就自保持，只能由复位上升沿清除。（已有 LTL 公式；实际结论以检查记录为准）
- S3：跳闸状态下绝不允许燃料许可。（已有 LTL 公式；实际结论以检查记录为准）
- S4：无运行请求时不得给出燃料许可。（已有 LTL 公式；实际结论以检查记录为准）
- S5：无燃料许可时风门命令必须归零（防止停机后残留开度）。（已有 LTL 公式；实际结论以检查记录为准）
- S6：风门命令恒在 0..100 之间。（已有 LTL 公式；实际结论以检查记录为准）
- S7：氧量修正偏置恒在 ±10 之间。（已有 LTL 公式；实际结论以检查记录为准）
- S8：氧量分析仪故障当拍必须切除修正。（已有 LTL 公式；实际结论以检查记录为准）
- S9：故障判据：数据无效或超出 0..21 量程。（已有 LTL 公式；实际结论以检查记录为准）
- S10：修正系数与钳位后的合成值。（目前仅测试覆盖）

## 当前平台适配参考程序

```st
FUNCTION_BLOCK FB
VAR_INPUT
 runRequest : BOOL;
 flameOK : BOOL;
 o2Valid : BOOL;
 o2PV : REAL;
 baseAir : REAL;
 resetBtn : BOOL;
END_VAR
VAR_OUTPUT
 fuelPermit : BOOL;
 trimEnable : BOOL;
 airTrim : REAL;
 airCommand : REAL;
 tripLatched : BOOL;
 o2Fault : BOOL;
END_VAR
VAR
 prevReset : BOOL;
 tripMem : BOOL;
END_VAR
o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);
IF runRequest AND NOT flameOK THEN
 tripMem := TRUE;
ELSIF resetBtn AND NOT prevReset AND NOT runRequest AND NOT flameOK THEN
 tripMem := FALSE;
END_IF;
prevReset := resetBtn;
tripLatched := tripMem;
fuelPermit := runRequest AND flameOK AND NOT tripMem;
trimEnable := fuelPermit AND NOT o2Fault;
IF trimEnable THEN
 airTrim := 2.0 * (2.0 - o2PV);
 IF airTrim > 10.0 THEN airTrim := 10.0; END_IF;
 IF airTrim < -10.0 THEN airTrim := -10.0; END_IF;
ELSE
 airTrim := 0.0;
END_IF;
IF fuelPermit THEN
 airCommand := baseAir + airTrim;
 IF airCommand > 100.0 THEN airCommand := 100.0; END_IF;
 IF airCommand < 0.0 THEN airCommand := 0.0; END_IF;
ELSE
 airCommand := 0.0;
END_IF;
END_FUNCTION_BLOCK

```

## 当前测试用例（含期望值，供人工复核）

```json
[
  {
    "tc_id": "q1",
    "inputs": {
      "runRequest": false,
      "flameOK": false,
      "o2Valid": true,
      "o2PV": 4.0,
      "baseAir": 50.0,
      "resetBtn": false
    },
    "expected": {
      "o2Fault": false,
      "tripLatched": false,
      "fuelPermit": false,
      "trimEnable": false,
      "airTrim": 0.0,
      "airCommand": 0.0
    },
    "note": "停机初始：无故障、不跳闸、无燃料许可，风门命令归 0",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q2",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": true,
      "o2PV": 4.0,
      "baseAir": 50.0,
      "resetBtn": false
    },
    "expected": {
      "o2Fault": false,
      "fuelPermit": true,
      "trimEnable": true,
      "airTrim": -4.0,
      "airCommand": 46.0
    },
    "note": "正常运行：o2=4.0 → trim=2*(2-4)=-4，风门 46",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q3",
    "inputs": {
      "runRequest": true,
      "flameOK": false,
      "o2Valid": true,
      "o2PV": 4.0,
      "baseAir": 50.0,
      "resetBtn": false
    },
    "expected": {
      "tripLatched": true,
      "fuelPermit": false,
      "trimEnable": false,
      "airTrim": 0.0,
      "airCommand": 0.0
    },
    "note": "运行中熄火：**当拍**跳闸并切断燃料（不得等到下一拍）",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q4",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": true,
      "o2PV": 4.0,
      "baseAir": 50.0,
      "resetBtn": false
    },
    "expected": {
      "tripLatched": true,
      "fuelPermit": false,
      "airCommand": 0.0
    },
    "note": "跳闸自保持：火焰恢复也不自动复位",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q5",
    "inputs": {
      "runRequest": false,
      "flameOK": false,
      "o2Valid": true,
      "o2PV": 4.0,
      "baseAir": 50.0,
      "resetBtn": true
    },
    "expected": {
      "tripLatched": false,
      "fuelPermit": false,
      "airCommand": 0.0
    },
    "note": "复位：runRequest=FALSE 且 flameOK=FALSE 时上升沿清除跳闸",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q6",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": false,
      "o2PV": 4.0,
      "baseAir": 50.0,
      "resetBtn": false
    },
    "expected": {
      "o2Fault": true,
      "fuelPermit": true,
      "trimEnable": false,
      "airTrim": 0.0,
      "airCommand": 50.0
    },
    "note": "分析仪无效：切除修正但**不**切燃料，风门只跟基础给定",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q7",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": true,
      "o2PV": 1.0,
      "baseAir": 50.0,
      "resetBtn": false
    },
    "expected": {
      "o2Fault": false,
      "trimEnable": true,
      "airTrim": 2.0,
      "airCommand": 52.0
    },
    "note": "恢复有效：o2 偏低 → 加风 +2",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q8",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": true,
      "o2PV": 5.5,
      "baseAir": 80.0,
      "resetBtn": false
    },
    "expected": {
      "airTrim": -7.0,
      "airCommand": 73.0
    },
    "note": "o2 偏高 → trim=-7，风门 73",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q9",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": true,
      "o2PV": 8.0,
      "baseAir": 95.0,
      "resetBtn": false
    },
    "expected": {
      "airTrim": -10.0,
      "airCommand": 85.0
    },
    "note": "【边界】原始 trim=2*(2-8)=-12，必须钳位到 -10",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q10",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": true,
      "o2PV": 1.0,
      "baseAir": 95.0,
      "resetBtn": false
    },
    "expected": {
      "airTrim": 2.0,
      "airCommand": 97.0
    },
    "note": "正修正：95+2=97，尚在范围内",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q11",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": true,
      "o2PV": 0.0,
      "baseAir": 99.0,
      "resetBtn": false
    },
    "expected": {
      "airTrim": 4.0,
      "airCommand": 100.0
    },
    "note": "【边界】99+4=103，风门命令必须钳位到 100",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q12",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": true,
      "o2PV": 21.0,
      "baseAir": 100.0,
      "resetBtn": false
    },
    "expected": {
      "o2Fault": false,
      "airTrim": -10.0,
      "airCommand": 90.0
    },
    "note": "【边界】o2=21.0 仍属合法量程（<=21），trim 钳位 -10",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q13",
    "inputs": {
      "runRequest": true,
      "flameOK": true,
      "o2Valid": true,
      "o2PV": 21.1,
      "baseAir": 100.0,
      "resetBtn": false
    },
    "expected": {
      "o2Fault": true,
      "trimEnable": false,
      "airTrim": 0.0,
      "airCommand": 100.0
    },
    "note": "【边界】o2=21.1 越界 → 判故障、切除修正",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  }
]
```
