# self-medium-05：合格蒸汽产量与净收益累计（闭区间判定 + 数据故障冻结）

状态：待人工复核；指定负责人刘晏铭。

## 建议核对

- 蒸汽和燃料流量 kg/s 与秒、吨的换算是否一致？
- 温度/压力闭区间端点、数据故障冻结、复位当拍不累计是否对应？
- 产量与燃料累计条件的差异、收益和成本题内常数是否写清楚？

## 题目与平台适配要求

写一个功能块 FB，按扫描周期累计锅炉的合格蒸汽产量、燃料消耗与净收益。
控制要求：
1. 合格判据：steamTemp 在 [447.0, 453.0] 且 steamPressure 在 [3750.0, 3850.0]（**闭区间**，端点合格）；
2. 本周期合格且 enable=TRUE 且无数据故障时，qualifiedTon += steamFlow * scanSeconds / 1000.0（kg/s × s ÷ 1000 → t）；无论是否合格，只要 enable 且无故障，fuelTon += fuelFlow * scanSeconds / 1000.0；
3. 数据故障判据：scanSeconds <= 0.0 或 scanSeconds > 10.0 或 steamFlow 不在 [0,90] 或 fuelFlow 不在 [0,6]；故障拍**不累计**，累计值保持不变；
4. resetBtn 上升沿：两个累计量清零，且**当拍不再累计**；
5. revenue = qualifiedTon * 280.0，cost = fuelTon * 1500.0，netProfit = revenue - cost，三者每拍都要更新（即使不累计）。
6. 所有累计量必须是非负的；enable=FALSE 时只更新判定位，不改累计量。
平台适配：原接口 dt（IEC 日期时间类型别名）统一重命名为 scanSeconds；单位秒、类型及原数字断言不变。

## 接口

|变量|方向|类型|说明|
|---|---|---|---|
|enable|输入|BOOL|计量使能|
|resetBtn|输入|BOOL|清零按钮（上升沿有效）|
|scanSeconds|输入|LREAL|本周期时长（s），合法 0 < dt <= 10|
|steamFlow|输入|LREAL|蒸汽流量（kg/s），合法 0..90|
|fuelFlow|输入|LREAL|燃料流量（kg/s），合法 0..6|
|steamTemp|输入|LREAL|蒸汽温度（℃）|
|steamPressure|输入|LREAL|蒸汽压力（kPa）|
|qualified|输出|BOOL|本周期蒸汽是否合格|
|dataFault|输出|BOOL|数据故障（参数越界）|
|qualifiedTon|输出|LREAL|累计合格蒸汽产量（t）|
|fuelTon|输出|LREAL|累计燃料消耗（t）|
|revenue|输出|LREAL|累计收入（元）|
|cost|输出|LREAL|累计成本（元）|
|netProfit|输出|LREAL|累计净收益（元）|

## 性质说明

- S1：合格判据：温度 447..453 ℃ 且 压力 3750..3850 kPa（闭区间）。（已有 LTL 公式；实际结论以检查记录为准）
- S2：累计产量与累计燃料消耗永远非负。（已有 LTL 公式；实际结论以检查记录为准）
- S3：复位上升沿当拍把两个累计量清零。（已有 LTL 公式；实际结论以检查记录为准）
- S4：数据故障判据：scanSeconds 不在 (0,10] 或流量越界。（已有 LTL 公式；实际结论以检查记录为准）
- S5：数据故障或未使能时，累计燃料在本拍保持不变。（已有 LTL 公式；实际结论以检查记录为准）
- S6：数据故障且未复位时，累计产量在本拍保持不变。（已有 LTL 公式；实际结论以检查记录为准）
- S7：收入与成本随累计量单调（不得出现负收入）。（已有 LTL 公式；实际结论以检查记录为准）
- S8：公开输入和累计输出的增量及收入成本关系；复位拍不累计，浮点容差 1e-6。（已有 LTL 公式；实际结论以检查记录为准）

## 当前平台适配参考程序

```st
FUNCTION_BLOCK FB
VAR_INPUT
 enable : BOOL;
 resetBtn : BOOL;
 scanSeconds : LREAL;
 steamFlow : LREAL;
 fuelFlow : LREAL;
 steamTemp : LREAL;
 steamPressure : LREAL;
END_VAR
VAR_OUTPUT
 qualified : BOOL;
 dataFault : BOOL;
 qualifiedTon : LREAL;
 fuelTon : LREAL;
 revenue : LREAL;
 cost : LREAL;
 netProfit : LREAL;
END_VAR
VAR
 prevReset : BOOL;
 qTon : LREAL;
 fTon : LREAL;
END_VAR
qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
 AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);
dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
 OR (steamFlow < 0.0) OR (steamFlow > 90.0)
 OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);
IF resetBtn AND NOT prevReset THEN
 qTon := 0.0;
 fTon := 0.0;
ELSIF enable AND NOT dataFault THEN
 fTon := fTon + fuelFlow * scanSeconds / 1000.0;
 IF qualified THEN
  qTon := qTon + steamFlow * scanSeconds / 1000.0;
 END_IF;
END_IF;
prevReset := resetBtn;
qualifiedTon := qTon;
fuelTon := fTon;
revenue := qTon * 280.0;
cost := fTon * 1500.0;
netProfit := revenue - cost;
END_FUNCTION_BLOCK

```

## 当前测试用例（含期望值，供人工复核）

```json
[
  {
    "tc_id": "q1",
    "inputs": {
      "enable": true,
      "resetBtn": false,
      "steamFlow": 20.0,
      "fuelFlow": 1.0,
      "steamTemp": 450.0,
      "steamPressure": 3800.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "qualified": true,
      "dataFault": false,
      "qualifiedTon": 0.02,
      "fuelTon": 0.001,
      "revenue": 5.6,
      "cost": 1.5,
      "netProfit": 4.1
    },
    "note": "正常：q=20*1/1000=0.02t，f=1*1/1000=0.001t",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q2",
    "inputs": {
      "enable": true,
      "resetBtn": false,
      "steamFlow": 20.0,
      "fuelFlow": 1.0,
      "steamTemp": 446.0,
      "steamPressure": 3800.0,
      "scanSeconds": 2.0
    },
    "expected": {
      "qualified": false,
      "dataFault": false,
      "qualifiedTon": 0.02,
      "fuelTon": 0.003,
      "revenue": 5.6,
      "cost": 4.5,
      "netProfit": 1.1
    },
    "note": "温度 446 不合格：只累计燃料，不累计产量",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q3",
    "inputs": {
      "enable": true,
      "resetBtn": false,
      "steamFlow": 20.0,
      "fuelFlow": 1.0,
      "steamTemp": 447.0,
      "steamPressure": 3750.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "qualified": true,
      "qualifiedTon": 0.04,
      "fuelTon": 0.004,
      "revenue": 11.2,
      "cost": 6.0,
      "netProfit": 5.2
    },
    "note": "【边界】447.0 与 3750.0 恰好合格（闭区间）",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q4",
    "inputs": {
      "enable": true,
      "resetBtn": false,
      "steamFlow": 20.0,
      "fuelFlow": 1.0,
      "steamTemp": 450.0,
      "steamPressure": 3800.0,
      "scanSeconds": 0.0
    },
    "expected": {
      "dataFault": true,
      "qualifiedTon": 0.04,
      "fuelTon": 0.004,
      "netProfit": 5.2
    },
    "note": "【边界】dt=0 判数据故障：本拍不累计，不得除零也不得写坏累计值",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q5",
    "inputs": {
      "enable": true,
      "resetBtn": true,
      "steamFlow": 20.0,
      "fuelFlow": 1.0,
      "steamTemp": 450.0,
      "steamPressure": 3800.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "qualifiedTon": 0.0,
      "fuelTon": 0.0,
      "revenue": 0.0,
      "cost": 0.0,
      "netProfit": 0.0
    },
    "note": "复位上升沿：累计量清零，当拍不累计",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q6",
    "inputs": {
      "enable": true,
      "resetBtn": false,
      "steamFlow": 0.0,
      "fuelFlow": 1.0,
      "steamTemp": 450.0,
      "steamPressure": 3800.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "qualifiedTon": 0.0,
      "fuelTon": 0.001,
      "revenue": 0.0,
      "cost": 1.5,
      "netProfit": -1.5
    },
    "note": "只烧燃料不产汽：净收益为负，累计燃料照记",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q7",
    "inputs": {
      "enable": true,
      "resetBtn": false,
      "steamFlow": 20.0,
      "fuelFlow": 1.0,
      "steamTemp": 450.0,
      "steamPressure": 3800.0,
      "scanSeconds": 11.0
    },
    "expected": {
      "dataFault": true,
      "fuelTon": 0.001
    },
    "note": "【边界】dt=11 超上限 → 故障，不累计",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q8",
    "inputs": {
      "enable": true,
      "resetBtn": false,
      "steamFlow": 91.0,
      "fuelFlow": 1.0,
      "steamTemp": 450.0,
      "steamPressure": 3800.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "dataFault": true,
      "fuelTon": 0.001,
      "qualifiedTon": 0.0
    },
    "note": "【边界】蒸汽流量 91 超量程 → 故障",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q9",
    "inputs": {
      "enable": true,
      "resetBtn": false,
      "steamFlow": 90.0,
      "fuelFlow": 6.0,
      "steamTemp": 453.0,
      "steamPressure": 3850.0,
      "scanSeconds": 2.0
    },
    "expected": {
      "qualified": true,
      "dataFault": false,
      "qualifiedTon": 0.18,
      "fuelTon": 0.013,
      "revenue": 50.4,
      "cost": 19.5,
      "netProfit": 30.9
    },
    "note": "【边界】四个量全部取合法上界：90*2/1000=0.18t，6*2/1000=0.012t",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q10",
    "inputs": {
      "enable": false,
      "resetBtn": false,
      "steamFlow": 50.0,
      "fuelFlow": 2.0,
      "steamTemp": 451.0,
      "steamPressure": 3800.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "qualified": true,
      "qualifiedTon": 0.18,
      "fuelTon": 0.013,
      "netProfit": 30.9
    },
    "note": "enable=FALSE：只更新判定位，累计量保持（不得静默累加）",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q11",
    "inputs": {
      "enable": true,
      "resetBtn": false,
      "steamFlow": 50.0,
      "fuelFlow": 6.1,
      "steamTemp": 451.0,
      "steamPressure": 3800.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "dataFault": true,
      "fuelTon": 0.013
    },
    "note": "【边界】燃料 6.1 超量程 → 故障",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  }
]
```
