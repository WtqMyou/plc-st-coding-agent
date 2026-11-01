# self-hard-06：蒸汽母管超压联锁与故障线索诊断（按位编码 + 足迹保留）

状态：待人工复核；指定负责人刘晏铭。

## 建议核对

- 压力单位 kPa，4500 跳闸与 4200 复位的闭区间和滞环是否明确？
- 压力数据失效与复位的优先关系是否清楚？
- 卡滞连续三拍及中断清零、线索位和历史足迹是否一致？三拍依赖扫描周期的假设是否应补充？

## 题目与平台适配要求

写一个功能块 FB，实现母管超压联锁，并在跳闸时记录**故障线索**。
控制要求：
1. 压力有效判据 pressureValid；>= 4500.0 kPa 判超压；
2. 跳闸条件（任一成立）：runRequest 且 pressureValid 且 pressure >= 4500.0；runRequest 且 NOT pressureValid（数据失效按最坏情况处理）；跳闸与本拍线索同拍生效；
3. tripLatched 自保持；清除条件：resetBtn 上升沿 且 NOT runRequest 且 pressureValid 且 pressure <= 4200.0（滞环，防抖动）；
4. 线索位（currentCauseMask，WORD，本拍重新计算）：bit0=1 变送器失效；bit1=2 减温减压阀卡滞（outletCmd>=50 且 outletFeedback<=10 连续 **3 拍及以上**，每拍须同时满足运行、压力有效且压力>=4500；任一中断清零）；bit2=4 燃烧过剩（fuelFlow >= 4.0 且 steamFlow <= 10.0）；若超压但以上线索都不成立，置 bit3=8（未定位）；NOT runRequest 时线索为 0；
5. latchedCauseMask：tripLatched 为 TRUE 时把 currentCauseMask **按位或**并入（32 位字，不会溢出），复位时清零；
6. fuelPermit = runRequest AND NOT tripLatched；diagnosticActive = (currentCauseMask <> 0)。

## 接口

|变量|方向|类型|说明|
|---|---|---|---|
|runRequest|输入|BOOL|运行请求|
|pressure|输入|REAL|母管压力（kPa）|
|pressureValid|输入|BOOL|压力变送器数据有效|
|fuelFlow|输入|REAL|燃料流量（kg/s）|
|steamFlow|输入|REAL|蒸汽流量（kg/s）|
|outletCmd|输入|INT|减温减压阀开度命令（%）|
|outletFeedback|输入|INT|减温减压阀开度反馈（%）|
|resetBtn|输入|BOOL|复位按钮（上升沿有效）|
|tripLatched|输出|BOOL|超压跳闸自保持|
|fuelPermit|输出|BOOL|燃料许可|
|currentCauseMask|输出|WORD|本周期诊断线索位掩码|
|latchedCauseMask|输出|WORD|跳闸时的线索累积掩码|
|diagnosticActive|输出|BOOL|存在有效诊断线索|

## 性质说明

- S1：压力变送器失效且仍在运行时，必须当拍跳闸并切除燃料。（已有 LTL 公式；实际结论以检查记录为准）
- S2：母管压力达到 4500 kPa（数据有效）时必须当拍跳闸。（已有 LTL 公式；实际结论以检查记录为准）
- S3：跳闸状态下绝不允许燃料许可。（已有 LTL 公式；实际结论以检查记录为准）
- S4：跳闸自保持，非复位上升沿不得自动清除。（已有 LTL 公式；实际结论以检查记录为准）
- S5：无运行请求时本周期线索掩码必须为 0。（已有 LTL 公式；实际结论以检查记录为准）
- S6：压力未越限且数据有效时不产生线索。（已有 LTL 公式；实际结论以检查记录为准）
- S7：诊断有效位与线索掩码一致。（已有 LTL 公式；实际结论以检查记录为准）
- S8：复位条件满足时跳闸必须清除。（已有 LTL 公式；实际结论以检查记录为准）
- S9：诊断线索的位含义与累积方式（按位或并入足迹）。（目前仅测试覆盖）

## 当前平台适配参考程序

```st
FUNCTION_BLOCK FB
VAR_INPUT
 runRequest : BOOL;
 pressure : REAL;
 pressureValid : BOOL;
 fuelFlow : REAL;
 steamFlow : REAL;
 outletCmd : INT;
 outletFeedback : INT;
 resetBtn : BOOL;
END_VAR
VAR_OUTPUT
 tripLatched : BOOL;
 fuelPermit : BOOL;
 currentCauseMask : WORD;
 latchedCauseMask : WORD;
 diagnosticActive : BOOL;
END_VAR
VAR
 prevReset : BOOL;
 tripMem : BOOL;
 latMem : WORD;
 valveCnt : INT;
END_VAR
currentCauseMask := 0;
IF resetBtn AND NOT prevReset AND NOT runRequest AND pressureValid
 AND (pressure <= 4200.0) THEN
 tripMem := FALSE;
 latMem := 0;
 valveCnt := 0;
END_IF;
prevReset := resetBtn;
IF NOT runRequest THEN
 valveCnt := 0;
ELSIF NOT pressureValid THEN
 currentCauseMask := 16#0001;
 valveCnt := 0;
 tripMem := TRUE;
ELSIF pressureValid AND (pressure >= 4500.0) THEN
 IF (outletCmd >= 50) AND (outletFeedback <= 10) THEN
  valveCnt := valveCnt + 1;
  IF valveCnt > 3 THEN valveCnt := 3; END_IF;
 ELSE
  valveCnt := 0;
 END_IF;
 IF valveCnt >= 3 THEN
  currentCauseMask := currentCauseMask OR 16#0002;
 END_IF;
 IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
  currentCauseMask := currentCauseMask OR 16#0004;
 END_IF;
 IF currentCauseMask = 0 THEN
  currentCauseMask := 16#0008;
 END_IF;
 tripMem := TRUE;
ELSE
 valveCnt := 0;
END_IF;
IF tripMem THEN
 latMem := latMem OR currentCauseMask;
END_IF;
tripLatched := tripMem;
latchedCauseMask := latMem;
diagnosticActive := (currentCauseMask <> 0);
fuelPermit := runRequest AND NOT tripMem;
END_FUNCTION_BLOCK

```

## 当前测试用例（含期望值，供人工复核）

```json
[
  {
    "tc_id": "q1",
    "inputs": {
      "runRequest": false,
      "pressure": 4000.0,
      "pressureValid": true,
      "fuelFlow": 1.0,
      "steamFlow": 20.0,
      "outletCmd": 0,
      "outletFeedback": 0,
      "resetBtn": false
    },
    "expected": {
      "tripLatched": false,
      "fuelPermit": false,
      "currentCauseMask": 0,
      "latchedCauseMask": 0,
      "diagnosticActive": false
    },
    "note": "停机初始：无跳闸、无线索",
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
      "pressure": 4200.0,
      "pressureValid": true,
      "fuelFlow": 2.0,
      "steamFlow": 20.0,
      "outletCmd": 60,
      "outletFeedback": 60,
      "resetBtn": false
    },
    "expected": {
      "tripLatched": false,
      "fuelPermit": true,
      "currentCauseMask": 0
    },
    "note": "压力 4200 未达 4500：允许燃料，无线索",
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
      "pressure": 4600.0,
      "pressureValid": true,
      "fuelFlow": 2.0,
      "steamFlow": 20.0,
      "outletCmd": 60,
      "outletFeedback": 60,
      "resetBtn": false
    },
    "expected": {
      "tripLatched": true,
      "fuelPermit": false,
      "currentCauseMask": 8,
      "latchedCauseMask": 8,
      "diagnosticActive": true
    },
    "note": "超压但阀位正常、燃烧正常 → 线索=8（未定位）",
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
      "pressure": 4600.0,
      "pressureValid": true,
      "fuelFlow": 2.0,
      "steamFlow": 20.0,
      "outletCmd": 80,
      "outletFeedback": 0,
      "resetBtn": false
    },
    "expected": {
      "tripLatched": true,
      "currentCauseMask": 8,
      "latchedCauseMask": 8
    },
    "note": "阀卡滞第 1 拍（计数 1，未达 3 拍判据）仍只报 8",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q5",
    "inputs": {
      "runRequest": true,
      "pressure": 4600.0,
      "pressureValid": true,
      "fuelFlow": 4.5,
      "steamFlow": 5.0,
      "outletCmd": 80,
      "outletFeedback": 0,
      "resetBtn": false
    },
    "expected": {
      "currentCauseMask": 4,
      "latchedCauseMask": 12
    },
    "note": "阀计数 2 + 燃烧过剩 → 位2 已置（8|4=12）",
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
      "pressure": 4600.0,
      "pressureValid": true,
      "fuelFlow": 4.5,
      "steamFlow": 5.0,
      "outletCmd": 80,
      "outletFeedback": 0,
      "resetBtn": false
    },
    "expected": {
      "currentCauseMask": 6,
      "latchedCauseMask": 14
    },
    "note": "阀计数达 3 → 位1 置；与位2 合并得 6（14=8|4|2）",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q7",
    "inputs": {
      "runRequest": false,
      "pressure": 4000.0,
      "pressureValid": true,
      "fuelFlow": 0.0,
      "steamFlow": 0.0,
      "outletCmd": 0,
      "outletFeedback": 0,
      "resetBtn": false
    },
    "expected": {
      "tripLatched": true,
      "fuelPermit": false,
      "currentCauseMask": 0,
      "latchedCauseMask": 14,
      "diagnosticActive": false
    },
    "note": "停机后本拍无线索，但**已累积**的足迹必须保留（供事后诊断）",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q8",
    "inputs": {
      "runRequest": false,
      "pressure": 4000.0,
      "pressureValid": true,
      "fuelFlow": 0.0,
      "steamFlow": 0.0,
      "outletCmd": 0,
      "outletFeedback": 0,
      "resetBtn": true
    },
    "expected": {
      "tripLatched": false,
      "currentCauseMask": 0,
      "latchedCauseMask": 0
    },
    "note": "复位：runRequest=FALSE、压力已回落到 <=4200 → 跳闸与足迹一起清",
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
      "pressure": 4600.0,
      "pressureValid": true,
      "fuelFlow": 4.5,
      "steamFlow": 5.0,
      "outletCmd": 0,
      "outletFeedback": 0,
      "resetBtn": false
    },
    "expected": {
      "tripLatched": true,
      "currentCauseMask": 4,
      "latchedCauseMask": 4
    },
    "note": "阀命令未达 50 → 不计卡滞；只剩燃烧过剩线索",
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
      "pressure": 4600.0,
      "pressureValid": false,
      "fuelFlow": 4.5,
      "steamFlow": 5.0,
      "outletCmd": 90,
      "outletFeedback": 0,
      "resetBtn": false
    },
    "expected": {
      "tripLatched": true,
      "currentCauseMask": 1,
      "latchedCauseMask": 5
    },
    "note": "变送器失效：线索=1（优先于压力判据），并入累积 5",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  }
]
```
