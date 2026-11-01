# self-hard-07：串级 PI 手自动无扰切换（积分预置 + 切换拍保持）

状态：待人工复核；指定负责人刘晏铭。

## 建议核对

- 三模式含义、初始化/故障/复位/模式切换的优先关系是否一致？
- 切换当拍保持阀位、不积分，以及积分预置和输出限幅是否对应？
- 给定 PI 参数、流量单位、手动输入范围和有效扫描周期的假设是否完整？

## 题目与平台适配要求

写一个功能块 FB，实现温度-流量串级 PI 控制的三模式无扰切换。
控制要求：
1. mode：0=手动、1=外环手动/内环自动、2=串级全自动；mode 不在 0..2、scanSeconds<=0 或 scanSeconds>10 判 fault；
2. 初始化、复位上升沿、fault 三者的当拍：flowSP = manualFlowSP、valveCommand = manualValve，并把积分项预置为无扰值：iT = flowSP - KpT*(tempSP-tempPV)，iF = valveCommand - KpF*(flowSP-flowPV)（KpT=1.0，KpF=2.0）；
3. **模式切换的当拍不做积分**：阀位保持上一拍；切到 mode=2 时 flowSP 也保持上一拍，切到其它模式时 flowSP 跟 manualFlowSP；切换拍同时按上面公式重算 iT、iF；
4. 正常运算拍（normalMode=TRUE）：
   mode=0：flowSP=manualFlowSP、valveCommand=manualValve，重算 iT、iF；
   mode=1：flowSP=manualFlowSP、iT 按公式跟踪；eF=flowSP-flowPV，iF += KiF*eF*scanSeconds（KiF=0.5），valveCommand=clamp(KpF*eF+iF,0,100)，随后 iF=valveCommand-KpF*eF；
   mode=2：eT=tempSP-tempPV，iT += KiT*eT*scanSeconds（KiT=0.2），flowSP=clamp(KpT*eT+iT,0,50)，iT=flowSP-KpT*eT；再按 mode=1 的公式算内环；
5. 模式切换的识别：非初始化拍比较 mode 与内部上一模式；即使连续两拍切换也必须识别；初始化记录当前 mode；下一合法非复位拍 mode 未变则正常运算（与 q2 一致），mode 变化则切换保持；
6. normalMode 输出：本拍按正常 PI 规则运算则为 TRUE，初始化/切换/故障拍为 FALSE。调用方保证 manualFlowSP 在 [0,50]、manualValve 在 [0,100]；输入均为有限数。
平台适配：原接口 dt（IEC 日期时间类型别名）统一重命名为 scanSeconds；单位秒、类型及原数字断言不变。

## 接口

|变量|方向|类型|说明|
|---|---|---|---|
|mode|输入|INT|0=手动 1=外环手动/内环自动 2=串级全自动|
|resetBtn|输入|BOOL|复位（上升沿）|
|scanSeconds|输入|REAL|本周期时长（s），合法 0 < dt <= 10|
|tempSP|输入|REAL|温度设定（℃）|
|tempPV|输入|REAL|温度测量（℃）|
|flowPV|输入|REAL|流量测量（t/h）|
|manualFlowSP|输入|REAL|流量设定手操值（t/h）|
|manualValve|输入|REAL|阀位手操值（%）|
|flowSP|输出|REAL|流量设定输出（t/h），钳位 0..50|
|valveCommand|输出|REAL|阀位命令（%），钳位 0..100|
|fault|输出|BOOL|模式或参数非法|
|normalMode|输出|BOOL|本拍按正常 PI 规则运算（非初始化/切换拍）|

## 性质说明

- S1：流量设定输出恒在 0..50 t/h 之间。（已有 LTL 公式；实际结论以检查记录为准）
- S2：阀位命令恒在 0..100 % 之间。（已有 LTL 公式；实际结论以检查记录为准）
- S3：模式切换的当拍阀位命令必须保持上一拍（无扰切换的核心）。（已有 LTL 公式；实际结论以检查记录为准）
- S4：切入串级模式的当拍，流量设定必须保持上一拍值。（已有 LTL 公式；实际结论以检查记录为准）
- S5：故障拍退回无扰跟踪：流量设定跟手操、阀位跟手操。（已有 LTL 公式；实际结论以检查记录为准）
- S6：正常运算拍必须处于合法模式且无故障。（已有 LTL 公式；实际结论以检查记录为准）
- S7：积分项递推与无扰预置（内环/外环）。（目前仅测试覆盖）

## 当前平台适配参考程序

```st
FUNCTION_BLOCK FB
VAR_INPUT
 mode : INT;
 resetBtn : BOOL;
 scanSeconds : REAL;
 tempSP : REAL;
 tempPV : REAL;
 flowPV : REAL;
 manualFlowSP : REAL;
 manualValve : REAL;
END_VAR
VAR_OUTPUT
 flowSP : REAL;
 valveCommand : REAL;
 fault : BOOL;
 normalMode : BOOL;
END_VAR
VAR
 prevReset : BOOL;
 initDone : BOOL;
 lastMode : INT;
 accT : REAL;
 accF : REAL;
 oFlow : REAL;
 oValve : REAL;
 eTemp : REAL;
 eFlow : REAL;
 trial : REAL;
 normalMem : BOOL;
END_VAR
fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
normalMem := FALSE;
IF (NOT initDone) OR (resetBtn AND NOT prevReset) OR fault THEN
 oFlow := manualFlowSP;
 oValve := manualValve;
 accT := oFlow - 1.0 * (tempSP - tempPV);
 accF := oValve - 2.0 * (oFlow - flowPV);
 lastMode := mode;
 initDone := TRUE;
ELSIF lastMode <> mode THEN
 IF mode <> 2 THEN
  oFlow := manualFlowSP;
 END_IF;
 accT := oFlow - 1.0 * (tempSP - tempPV);
 accF := oValve - 2.0 * (oFlow - flowPV);
 lastMode := mode;
ELSE
 normalMem := TRUE;
 IF mode = 0 THEN
  oFlow := manualFlowSP;
  oValve := manualValve;
  accT := oFlow - 1.0 * (tempSP - tempPV);
  accF := oValve - 2.0 * (oFlow - flowPV);
 ELSIF mode = 1 THEN
  oFlow := manualFlowSP;
  accT := oFlow - 1.0 * (tempSP - tempPV);
  eFlow := oFlow - flowPV;
  trial := accF + 0.5 * eFlow * scanSeconds;
  oValve := 2.0 * eFlow + trial;
  IF oValve > 100.0 THEN oValve := 100.0; END_IF;
  IF oValve < 0.0 THEN oValve := 0.0; END_IF;
  accF := oValve - 2.0 * eFlow;
 ELSE
  eTemp := tempSP - tempPV;
  trial := accT + 0.2 * eTemp * scanSeconds;
  oFlow := 1.0 * eTemp + trial;
  IF oFlow > 50.0 THEN oFlow := 50.0; END_IF;
  IF oFlow < 0.0 THEN oFlow := 0.0; END_IF;
  accT := oFlow - 1.0 * eTemp;
  eFlow := oFlow - flowPV;
  trial := accF + 0.5 * eFlow * scanSeconds;
  oValve := 2.0 * eFlow + trial;
  IF oValve > 100.0 THEN oValve := 100.0; END_IF;
  IF oValve < 0.0 THEN oValve := 0.0; END_IF;
  accF := oValve - 2.0 * eFlow;
 END_IF;
END_IF;
prevReset := resetBtn;
flowSP := oFlow;
valveCommand := oValve;
normalMode := normalMem;
END_FUNCTION_BLOCK

```

## 当前测试用例（含期望值，供人工复核）

```json
[
  {
    "tc_id": "q1",
    "inputs": {
      "mode": 0,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 40.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "fault": false,
      "flowSP": 10.0,
      "valveCommand": 40.0,
      "normalMode": false
    },
    "note": "初始化拍：跟踪手操值，并把积分项预置成无扰初值",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q2",
    "inputs": {
      "mode": 0,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 40.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "flowSP": 10.0,
      "valveCommand": 40.0,
      "normalMode": true
    },
    "note": "手动稳定拍：直接跟手操值，积分项持续跟踪",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q3",
    "inputs": {
      "mode": 1,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 40.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "flowSP": 10.0,
      "valveCommand": 40.0,
      "normalMode": false
    },
    "note": "切到模式 1 的当拍：**不做积分**，阀位保持上一拍 40",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q4",
    "inputs": {
      "mode": 1,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 40.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "flowSP": 10.0,
      "valveCommand": 40.0,
      "normalMode": true
    },
    "note": "模式 1 正常拍：eF=0 → 阀位不变",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q5",
    "inputs": {
      "mode": 2,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 40.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "flowSP": 10.0,
      "valveCommand": 40.0,
      "normalMode": false
    },
    "note": "切到串级：流量设定必须**保持**上一拍值（不得跳到手操值）",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q6",
    "inputs": {
      "mode": 2,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 40.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "flowSP": 12.0,
      "valveCommand": 45.0,
      "normalMode": true
    },
    "note": "串级第一正常拍：外环 eT=10 → flowSP=12，内环出 45",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q7",
    "inputs": {
      "mode": 2,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 40.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "flowSP": 14.0,
      "valveCommand": 51.0,
      "normalMode": true
    },
    "note": "串级第二拍：积分继续累积 → 14 / 51",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q8",
    "inputs": {
      "mode": 0,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 20.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "flowSP": 10.0,
      "valveCommand": 51.0,
      "normalMode": false
    },
    "note": "切回手动当拍：阀位保持 51（不跟手操 20），避免突跳",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q9",
    "inputs": {
      "mode": 0,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 20.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "flowSP": 10.0,
      "valveCommand": 20.0,
      "normalMode": true
    },
    "note": "手动正常拍：跟手操 20，并把积分项重新预置成 20",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q10",
    "inputs": {
      "mode": 1,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 30.0,
      "scanSeconds": 0.0
    },
    "expected": {
      "fault": true,
      "flowSP": 10.0,
      "valveCommand": 30.0,
      "normalMode": false
    },
    "note": "【边界】dt=0 → 故障，退回无扰跟踪并置 normalMode=FALSE",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q11",
    "inputs": {
      "mode": 3,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 10.0,
      "manualFlowSP": 10.0,
      "manualValve": 30.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "fault": true,
      "valveCommand": 30.0,
      "normalMode": false
    },
    "note": "【边界】mode=3 非法 → 故障；不得按未知模式继续积分",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q12",
    "inputs": {
      "mode": 1,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 20.0,
      "manualFlowSP": 10.0,
      "manualValve": 30.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "fault": false,
      "flowSP": 10.0,
      "valveCommand": 30.0,
      "normalMode": false
    },
    "note": "从非法模式恢复：仍按切换拍处理，阀位保持",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  },
  {
    "tc_id": "q13",
    "inputs": {
      "mode": 1,
      "resetBtn": false,
      "tempSP": 100.0,
      "tempPV": 90.0,
      "flowPV": 20.0,
      "manualFlowSP": 10.0,
      "manualValve": 30.0,
      "scanSeconds": 1.0
    },
    "expected": {
      "flowSP": 10.0,
      "valveCommand": 25.0,
      "normalMode": true
    },
    "note": "模式 1 正常拍：eF=10-20=-10，iF=50（q12 预置）→ 阀位 clamp(2*(-10)+50)=25",
    "const_inputs": {},
    "init": {},
    "mode": "sequence",
    "cycles": 1,
    "expect_full": false
  }
]
```
