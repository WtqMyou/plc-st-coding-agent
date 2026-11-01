# self-medium-06：温度模糊控制与输出钳位（重心法 + 历史误差清除）

状态：待人工复核；指定负责人刘晏铭。

## 建议核对

- 误差及误差变化率的单位、采样周期与归一化范围是否清楚？
- 九条规则和加权输出、功率限幅与修正量的区别是否一致？
- 首次扫描、禁用、故障和复位清除历史后的恢复行为是否覆盖？

## 题目与平台适配要求

写一个功能块 FB，用九条规则的温度模糊控制器计算加热功率。
控制要求：
1. e = setpoint - temperature；de = (e - ePrev) / scanSeconds，**首拍**或历史被清除时 de = 0；
2. x = clamp(e / 10.0, -1, 1)，y = clamp(de / 2.0, -1, 1)；
3. 隶属度：μN(z)=max(-z,0)、μZ(z)=1-|z|、μP(z)=max(z,0)；
4. 九条规则的单点输出：N×N=-30、N×Z=-20、N×P=-10、Z×N=-10、Z×Z=0、Z×P=10、P×N=10、P×Z=20、P×P=30；correction = Σ(w·c)/Σw（重心法），Σw=0 时 correction=0；
5. power = clamp(bias + correction, 0, 100)，**correction 不钳位**；
6. fault = NOT sensorValid OR scanSeconds <= 0.0 OR scanSeconds > 10.0；fault、enable=FALSE 或 resetBtn 上升沿时：power=0、correction=0，并清除历史（ePrev=0、历史标志=FALSE）。
平台适配：原接口 dt（IEC 日期时间类型别名）统一重命名为 scanSeconds；单位秒、类型及原数字断言不变。

## 接口

|变量|方向|类型|说明|
|---|---|---|---|
|enable|输入|BOOL|自动投入|
|resetBtn|输入|BOOL|复位（上升沿清除历史误差）|
|sensorValid|输入|BOOL|温度传感器数据有效|
|setpoint|输入|REAL|温度设定值（℃）|
|temperature|输入|REAL|温度测量值（℃）|
|scanSeconds|输入|REAL|本周期时长（s），合法 0 < dt <= 10|
|bias|输入|REAL|基础输出（%）|
|power|输出|REAL|加热功率输出（%），钳位 0..100|
|correction|输出|REAL|模糊修正量（%）|
|fault|输出|BOOL|传感器或参数故障|

## 性质说明

- S1：加热功率恒在 0..100 之间。（已有 LTL 公式；实际结论以检查记录为准）
- S2：模糊修正量恒在 ±30 之间（九个单点输出量的极值）。（已有 LTL 公式；实际结论以检查记录为准）
- S3：未投入、复位上升沿或故障时，输出与修正必须归零。（已有 LTL 公式；实际结论以检查记录为准）
- S4：故障判据：传感器无效或 scanSeconds 越界。（已有 LTL 公式；实际结论以检查记录为准）
- S5：传感器无效必然判故障（不允许用坏数据继续闭环）。（已有 LTL 公式；实际结论以检查记录为准）
- S6：有效工作拍功率为 bias 加修正后的 0..100 钳位；停用、故障或复位拍为零。（已有 LTL 公式；实际结论以检查记录为准）

## 当前平台适配参考程序

```st
FUNCTION_BLOCK FB
VAR_INPUT
 enable : BOOL;
 resetBtn : BOOL;
 sensorValid : BOOL;
 setpoint : REAL;
 temperature : REAL;
 scanSeconds : REAL;
 bias : REAL;
END_VAR
VAR_OUTPUT
 power : REAL;
 correction : REAL;
 fault : BOOL;
END_VAR
VAR
 prevReset : BOOL;
 prevE : REAL;
 hasHist : BOOL;
 eNow : REAL;
 eDe : REAL;
 xx : REAL;
 yy : REAL;
 mx : REAL;
 zx : REAL;
 px : REAL;
 my : REAL;
 zy : REAL;
 py : REAL;
 wsum : REAL;
 wc : REAL;
 cOut : REAL;
 edgeReset : BOOL;
END_VAR
fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
edgeReset := resetBtn AND NOT prevReset;
IF edgeReset OR (NOT enable) OR fault THEN
 cOut := 0.0;
 hasHist := FALSE;
 prevE := 0.0;
ELSE
 eNow := setpoint - temperature;
 IF hasHist THEN
  eDe := (eNow - prevE) / scanSeconds;
 ELSE
  eDe := 0.0;
 END_IF;
 xx := eNow / 10.0;
 IF xx > 1.0 THEN xx := 1.0; END_IF;
 IF xx < -1.0 THEN xx := -1.0; END_IF;
 yy := eDe / 2.0;
 IF yy > 1.0 THEN yy := 1.0; END_IF;
 IF yy < -1.0 THEN yy := -1.0; END_IF;
 mx := MAX(-xx, 0.0);
 zx := 1.0 - ABS(xx);
 px := MAX(xx, 0.0);
 my := MAX(-yy, 0.0);
 zy := 1.0 - ABS(yy);
 py := MAX(yy, 0.0);
 wsum := mx * my + mx * zy + mx * py + zx * my + zx * zy + zx * py
  + px * my + px * zy + px * py;
 wc := mx * my * (-30.0) + mx * zy * (-20.0) + mx * py * (-10.0)
  + zx * my * (-10.0) + zx * zy * 0.0 + zx * py * 10.0
  + px * my * 10.0 + px * zy * 20.0 + px * py * 30.0;
 IF wsum > 0.0 THEN
  cOut := wc / wsum;
 ELSE
  cOut := 0.0;
 END_IF;
 prevE := eNow;
 hasHist := TRUE;
END_IF;
prevReset := resetBtn;
correction := cOut;
IF edgeReset OR (NOT enable) OR fault THEN
 power := 0.0;
ELSE
 power := bias + cOut;
 IF power > 100.0 THEN power := 100.0; END_IF;
 IF power < 0.0 THEN power := 0.0; END_IF;
END_IF;
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
      "sensorValid": true,
      "setpoint": 100.0,
      "temperature": 90.0,
      "bias": 50.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "fault": false,
      "correction": 20.0,
      "power": 70.0
    },
    "note": "首拍无历史：de=0，x=1.0/y=0 → 只踩 Z×P 规则，修正 +20",
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
      "sensorValid": true,
      "setpoint": 100.0,
      "temperature": 92.0,
      "bias": 50.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "correction": 6.0,
      "power": 56.0
    },
    "note": "e=8、de=(8-10)/1=-2 → x=0.8/y=-1：命中 Z×N(-10) 与 P×N(+10)，重心 = (-2+8)/1 = +6",
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
      "sensorValid": true,
      "setpoint": 100.0,
      "temperature": 100.0,
      "bias": 50.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "correction": -10.0,
      "power": 40.0
    },
    "note": "e=0、de=-8 → 命中 Z×N，修正 -10（误差为零也要抑制负向趋势）",
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
      "sensorValid": true,
      "setpoint": 100.0,
      "temperature": 98.0,
      "bias": 50.0,
      "scanSeconds": 2.0
    },
    "expected": {
      "correction": 9.0,
      "power": 59.0
    },
    "note": "三邻域同时激活：x=0.2/y=0.5 → 权重 Z×P(.4)、P×Z(.2)、P×P(.3) 与 P×Z 归一分母1 → 修正 (+4+2+3)/1 = 9.0",
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
      "resetBtn": false,
      "sensorValid": false,
      "setpoint": 100.0,
      "temperature": 98.0,
      "bias": 50.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "fault": true,
      "power": 0.0,
      "correction": 0.0
    },
    "note": "传感器故障：功率与修正都归零，并清除历史误差",
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
      "sensorValid": true,
      "setpoint": 100.0,
      "temperature": 100.0,
      "bias": 50.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "fault": false,
      "correction": 0.0,
      "power": 50.0
    },
    "note": "故障恢复首拍：历史已清除，按 de=0 处理，只出基础输出",
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
      "sensorValid": true,
      "setpoint": 100.0,
      "temperature": 90.0,
      "bias": 120.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "correction": 30.0,
      "power": 100.0
    },
    "note": "【边界】120+30=150 越界 → power 钳位 100，但 correction 仍报 30",
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
      "sensorValid": true,
      "setpoint": 100.0,
      "temperature": 90.0,
      "bias": 0.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "correction": 20.0,
      "power": 20.0
    },
    "note": "下界侧：0+20=20 在范围内，不触发钳位",
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
      "sensorValid": true,
      "setpoint": 100.0,
      "temperature": 90.0,
      "bias": 50.0,
      "scanSeconds": 0.0
    },
    "expected": {
      "fault": true,
      "power": 0.0,
      "correction": 0.0
    },
    "note": "【边界】dt=0 → 故障（既不能除零，也不允许按 0 周期积分）",
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
      "sensorValid": true,
      "setpoint": 100.0,
      "temperature": 90.0,
      "bias": 50.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "fault": false,
      "power": 0.0,
      "correction": 0.0
    },
    "note": "未投入自动：输出归零",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  }
]
```
