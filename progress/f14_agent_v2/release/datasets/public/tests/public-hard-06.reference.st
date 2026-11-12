(*
  Production Control — 参考解（public-hard-06）

  五个工位：上料(Feed) → 清洗(Wash) → 称重(Weight) → 烧结(Firing) → 成品(Output)，
  一台电机负责在工位间传送产品；每个工位一个到位传感器。

  需求编号：
    R1  Mode 开关：FALSE = 手动，TRUE = 自动
    R2  手动模式：ForwardButton 控制正转、ReverseButton 控制反转；正反转必须互锁，不能同时动作
    R3  自动模式：
        a) SensorFeed 检测到料 → 正转送到清洗站 → SensorWash 到位即停 → washComplete 后正转送称重
        b) SensorWeight 到位即停 → weightComplete 后按重量判定：100 ≤ weight ≤ 200 合格
        c) 不合格 → 发出 kick 剔除指令（一拍脉冲），产品被踢出，产线回到等待上料
        d) 合格 → 烧结温度按重量线性映射 100→500、200→550，输出 firingTemp，同时正转送烧结站
        e) SensorFiring 到位即停 → firingComplete 后正转送成品站
        f) SensorOutput 到位即停、CompletionLight 亮；产品被取走（SensorOutput=FALSE）灯灭，回到等待上料
    R4  模式切换：切到手动时自动流程复位（手动接管产线）；切回自动从等待上料重新开始
*)

FUNCTION_BLOCK FB
VAR_INPUT
  Mode : BOOL;                   (* R1 FALSE = 手动，TRUE = 自动 *)
  ForwardButton : BOOL;          (* R2 *)
  ReverseButton : BOOL;          (* R2 *)
  SensorFeed : BOOL;             (* 上料站到位传感器 *)
  SensorWash : BOOL;             (* 清洗站到位传感器 *)
  SensorWeight : BOOL;           (* 称重站到位传感器 *)
  SensorFiring : BOOL;           (* 烧结站到位传感器 *)
  SensorOutput : BOOL;           (* 成品站到位传感器 *)
  washComplete : BOOL;           (* 清洗完成信号 *)
  weightComplete : BOOL;         (* 称重完成信号 *)
  weight : REAL;                 (* 重量值（称重完成时有效） *)
  firingComplete : BOOL;         (* 烧结完成信号 *)
END_VAR
VAR_OUTPUT
  MotorForward : BOOL;           (* 电机正转 *)
  MotorReverse : BOOL;           (* 电机反转（仅手动可用） *)
  kick : BOOL;                   (* 不合格剔除指令 *)
  CompletionLight : BOOL;        (* 成品站完成灯 *)
  firingTemp : REAL;             (* 烧结温度设定值 *)
END_VAR
VAR
  state : INT;                   (* 0 等上料 / 1 送清洗 / 2 等清洗 / 3 送称重 / 4 等称重
                                    5 送烧结 / 6 等烧结 / 7 送成品 / 8 成品站 *)
  modePrev : BOOL;
END_VAR

(* 每拍先清零六个输出：手动/自动互斥由此保证，kick 是脉冲 *)
MotorForward := FALSE;
MotorReverse := FALSE;
kick := FALSE;
CompletionLight := FALSE;

(* R4 模式切换那一拍：自动流程复位，切回自动从"等待上料"重新开始 *)
IF Mode <> modePrev THEN
  state := 0;
END_IF
modePrev := Mode;

IF NOT Mode THEN
  (* R2 手动：两个按钮互锁，同按视为无效（谁都不动） *)
  IF ForwardButton AND (NOT ReverseButton) THEN
    MotorForward := TRUE;
  END_IF
  IF ReverseButton AND (NOT ForwardButton) THEN
    MotorReverse := TRUE;
  END_IF
ELSE
  (* R3 自动流程 *)
  CASE state OF
    0:
      (* 等上料：SensorFeed 检测到料就开始正转送清洗站 *)
      IF SensorFeed THEN
        state := 1;
        MotorForward := TRUE;
      END_IF
    1:
      (* 送到清洗站：到位即停 *)
      IF SensorWash THEN
        state := 2;
      ELSE
        MotorForward := TRUE;
      END_IF
    2:
      (* 等清洗完成 *)
      IF washComplete THEN
        state := 3;
        MotorForward := TRUE;
      END_IF
    3:
      (* 送到称重站：到位即停 *)
      IF SensorWeight THEN
        state := 4;
      ELSE
        MotorForward := TRUE;
      END_IF
    4:
      (* 等称重完成，按 R3b 判定合格与否 *)
      IF weightComplete THEN
        IF (weight >= 100.0) AND (weight <= 200.0) THEN
          (* R3d 合格：100..200 线性映射到 500..550（每 1 个单位重量 0.5 度） *)
          firingTemp := 500.0 + (weight - 100.0) * 0.5;
          state := 5;
          MotorForward := TRUE;
        ELSE
          (* R3c 不合格：剔除，一拍脉冲后回到等待上料；温度保持上一件合格品的值 *)
          kick := TRUE;
          state := 0;
        END_IF
      END_IF
    5:
      (* 送到烧结站：到位即停 *)
      IF SensorFiring THEN
        state := 6;
      ELSE
        MotorForward := TRUE;
      END_IF
    6:
      (* 等烧结完成 *)
      IF firingComplete THEN
        state := 7;
        MotorForward := TRUE;
      END_IF
    7:
      (* 送到成品站：到位即停，完成灯亮 *)
      IF SensorOutput THEN
        state := 8;
        CompletionLight := TRUE;
      ELSE
        MotorForward := TRUE;
      END_IF
    8:
      (* 成品站：产品还在则灯保持亮；被取走则灯灭并回到等待上料 *)
      IF SensorOutput THEN
        CompletionLight := TRUE;
      ELSE
        state := 0;
      END_IF
  ELSE
    state := 0;
  END_CASE
END_IF

END_FUNCTION_BLOCK
