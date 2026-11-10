(* =====================================================================
   public-medium-06  Slab Thickness Alarm and Fault History
   ---------------------------------------------------------------------
   平台边界（《公共题制作约定》§7）：
   * TIME 字面量恒为 0、TIME 加减恒为 0，所以"最小保持 500 ms"不能写成
     `x >= T#500ms`（在平台上恒 TRUE）。本解用**扫描周期计数**实现：
     1 拍 = 20 ms → 500 ms = 25 拍（ALARM_HOLD_CYCLES）。
   * 同理 `Slab_Runtime_Accumulator`（LINT）的"运行时间累积"改为**合格
     扫描周期计数**：每拍 +1 个周期，用例按拍数断言。输入 CycleTime 在
     本平台上恒为 0，不参与运算（需求 3 的计时语义由周期计数等价替代）。
   * 故障历史是 ARRAY[0..4] OF DINT 输出，引用解按 0..4 的自然顺序整表断言。
   ===================================================================== *)
FUNCTION_BLOCK FB_SlabThicknessMonitor
VAR_INPUT
  THICKNESS_FAULT : BOOL;          (* 厚度偏差超出允许公差 *)
  THICKNESS_SIGNAL_VALID : BOOL;   (* 厚度信号有效；FALSE 表示信号丢失 *)
  CUTTING_RUN : BOOL;              (* 切割设备实际运行状态 *)
  FaultTimestamp : DINT;           (* 当前时间戳（秒），作为故障记录标识 *)
  CycleTime : TIME;                (* 本次调用的实际间隔；平台上恒为 0 *)
END_VAR
VAR_OUTPUT
  THICKNESS_ALARM : BOOL;                           (* 带最小保持的厚度报警 *)
  Slab_Fault_Counter : UINT;                        (* 有效厚度故障次数 *)
  Slab_Runtime_Accumulator : LINT;                 (* 正常切割运行时间累积 *)
  Slab_Fault_History : ARRAY[0..4] OF DINT;         (* 最近 5 次故障时间戳，index 0 最新 *)
END_VAR
VAR
  faultActive : BOOL;      (* 有效故障 = 信号有效 AND 故障位 *)
  faultPrev : BOOL;        (* 上一拍的有效故障，用于上升沿检测 *)
  holdCycles : INT;        (* R1: 已保持的扫描拍数，25 拍 = 500 ms *)
  i : INT;
END_VAR

(* R5: 上电清零 —— 平台新实例的输出默认是 FALSE / 0，故障历史 5 个元素
   也由声明初值建为 0；计数、累积、历史在本程序里只会被加/被写，
   不会被"外部写入"，调用方也无法修改历史（VAR_OUTPUT 只读语义）。 *)

faultActive := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;

(* R1 / R4: 有效故障立即报警；故障持续期间保持；信号无效立即熄灭并清保持态 *)
IF NOT THICKNESS_SIGNAL_VALID THEN
  THICKNESS_ALARM := FALSE;
  holdCycles := 0;
ELSIF THICKNESS_FAULT THEN
  THICKNESS_ALARM := TRUE;
  holdCycles := 0;
ELSIF THICKNESS_ALARM THEN
  (* 故障已消失：至少再保持 25 拍（25 × 20 ms = 500 ms）才允许熄灭 *)
  IF holdCycles < 25 THEN
    holdCycles := holdCycles + 1;
  ELSE
    THICKNESS_ALARM := FALSE;
    holdCycles := 0;
  END_IF;
END_IF;

(* R2: 有效故障的 FALSE→TRUE 上升沿 → 计数 +1，时间戳写入 index 0，
   旧值向高下标移位，只保留最近 5 条。 *)
IF faultActive AND NOT faultPrev THEN
  IF Slab_Fault_Counter < 65535 THEN
    Slab_Fault_Counter := Slab_Fault_Counter + 1;
  END_IF;
  FOR i := 4 TO 1 BY -1 DO
    Slab_Fault_History[i] := Slab_Fault_History[i - 1];
  END_FOR;
  Slab_Fault_History[0] := FaultTimestamp;
END_IF;
faultPrev := faultActive;

(* R3 / R4: 只有"切割运行 + 信号有效 + 无故障"的拍才累积；否则原值保持。
   平台 TIME 不可用 → 累积的是合格扫描周期数（1 拍 = 1 个单位）。 *)
IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
  Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + 1;
END_IF;

END_FUNCTION_BLOCK
