(*
  Mechanical Arm Control — 参考解（public-hard-05）

  六动作：下/上/左/右/抓/放；四模式：手动/单步/单循环/连续（调用方保证互斥）。
  EmergencyStop 为反逻辑：FALSE = 急停触发，TRUE = 无急停。

  需求编号：
    R1  手动模式：按住按钮且未到位才动作，到位即停，松手即停
    R2  单步模式：按一次 Start 执行预置程序的"下一个"动作，动作完成即停等下一次确认
        预置程序：①下 ②抓 ③上 ④右 ⑤下 ⑥放 ⑦上 ⑧左，第 8 步之后回到第 1 步
    R3  单循环模式：按 Start 自动完成一整套搬运循环，最后一动（回左）到位后停在左上
    R4  连续模式：按 Start 后反复执行 R3 的搬运循环，不停
    R5  急停：任何模式任何时刻都能立刻停掉所有动作（FALSE 有效）；解除后从冻结的位置继续
        模式切换也立刻停掉自动动作，程序步回到起点
    R6  抓/放的完成反馈分别是 GripLimitSwitch / ReleaseLimitSwitch
*)

FUNCTION_BLOCK FB
VAR_INPUT
  (* 四模式，调用方保证同一时刻只有一个为 TRUE（本实现对同时为 TRUE 的容错 = 取高者） *)
  ManualMode : BOOL;             (* R1 *)
  SingleStepMode : BOOL;         (* R2 *)
  SingleCycleMode : BOOL;        (* R3 *)
  ContinuousMode : BOOL;         (* R4 *)
  EmergencyStop : BOOL;          (* R5 FALSE = 急停 *)
  Start : BOOL;                  (* R2/R3/R4 每按一次算一条指令 *)
  DownButton : BOOL;             (* R1 *)
  UpButton : BOOL;               (* R1 *)
  LeftButton : BOOL;             (* R1 *)
  RightButton : BOOL;            (* R1 *)
  GripButton : BOOL;             (* R1 *)
  ReleaseButton : BOOL;          (* R1 *)
  DownLimitSwitch : BOOL;        (* 到位反馈 *)
  UpLimitSwitch : BOOL;
  LeftLimitSwitch : BOOL;
  RightLimitSwitch : BOOL;
  GripLimitSwitch : BOOL;        (* R6 抓完成 *)
  ReleaseLimitSwitch : BOOL;     (* R6 放完成 *)
END_VAR
VAR_OUTPUT
  MoveDown : BOOL;
  MoveUp : BOOL;
  MoveLeft : BOOL;
  MoveRight : BOOL;
  ActivateGrip : BOOL;
  ActivateRelease : BOOL;
END_VAR
VAR
  startEdge : BOOL;              (* Start 上升沿 *)
  startPrev : BOOL;
  modeNow : INT;                 (* 本拍模式号 0 无 / 1 手动 / 2 单步 / 3 单循环 / 4 连续 *)
  modePrev : INT;
  fsStep : INT;                  (* 预置程序的当前步 1..8；0 = 未开始或本轮已结束 *)
  fsActive : BOOL;               (* 自动程序是否正在执行某个动作 *)
  fsDone : BOOL;                 (* 当前步的到位条件是否已满足 *)
  guard : INT;                   (* 每拍最多推进 8 步，防止一拍扫完多圈 *)
END_VAR

(* 每拍先把六个动作输出清零，后面按模式/状态逐位置位：急停或无模式时自然全 0（R5） *)
MoveDown := FALSE;
MoveUp := FALSE;
MoveLeft := FALSE;
MoveRight := FALSE;
ActivateGrip := FALSE;
ActivateRelease := FALSE;

(* 上升沿：按一次 Start 只发一条指令，按住不放不会连发 *)
startEdge := Start AND NOT startPrev;
startPrev := Start;

(* 模式号：四模式互斥由调用方保证；若同时为 TRUE 按 手动 > 单步 > 单循环 > 连续 取高者 *)
modeNow := 0;
IF ContinuousMode THEN
  modeNow := 4;
END_IF
IF SingleCycleMode THEN
  modeNow := 3;
END_IF
IF SingleStepMode THEN
  modeNow := 2;
END_IF
IF ManualMode THEN
  modeNow := 1;
END_IF

(* R5 模式切换：立刻停掉自动动作并把程序步清回起点，等新模式的指令 *)
IF modeNow <> modePrev THEN
  fsActive := FALSE;
  fsStep := 0;
  fsDone := FALSE;
END_IF
modePrev := modeNow;

IF NOT EmergencyStop THEN
  (* R5 急停压过一切：六个动作全部保持 0，程序步冻结（解除急停后从冻结点继续） *)
  fsDone := FALSE;
ELSIF modeNow = 1 THEN
  (* R1 手动模式：按住按钮且未到位才动作；一对互补按钮同按视为无效（不许同时动作） *)
  IF DownButton AND (NOT DownLimitSwitch) AND (NOT UpButton) THEN
    MoveDown := TRUE;
  END_IF
  IF UpButton AND (NOT UpLimitSwitch) AND (NOT DownButton) THEN
    MoveUp := TRUE;
  END_IF
  IF LeftButton AND (NOT LeftLimitSwitch) AND (NOT RightButton) THEN
    MoveLeft := TRUE;
  END_IF
  IF RightButton AND (NOT RightLimitSwitch) AND (NOT LeftButton) THEN
    MoveRight := TRUE;
  END_IF
  IF GripButton AND (NOT GripLimitSwitch) AND (NOT ReleaseButton) THEN
    ActivateGrip := TRUE;
  END_IF
  IF ReleaseButton AND (NOT ReleaseLimitSwitch) AND (NOT GripButton) THEN
    ActivateRelease := TRUE;
  END_IF
ELSIF (modeNow = 2) OR (modeNow = 3) OR (modeNow = 4) THEN
  (* R2/R3/R4 自动程序 *)
  IF startEdge AND (NOT fsActive) THEN
    IF modeNow = 2 THEN
      (* 单步：接着上次停下的位置继续；还没开始过就从第 1 步起 *)
      IF fsStep < 1 THEN
        fsStep := 1;
      END_IF
    ELSE
      (* 单循环 / 连续：每次启动都从第 1 步（下）重新开始一整轮 *)
      fsStep := 1;
    END_IF
    fsActive := TRUE;
  END_IF

  guard := 0;
  WHILE fsActive AND (guard < 8) DO
    guard := guard + 1;
    fsDone := FALSE;
    (* 预置程序：①下 ②抓 ③上 ④右 ⑤下 ⑥放 ⑦上 ⑧左 *)
    IF fsStep = 1 THEN
      IF DownLimitSwitch THEN fsDone := TRUE; ELSE MoveDown := TRUE; END_IF
    ELSIF fsStep = 2 THEN
      IF GripLimitSwitch THEN fsDone := TRUE; ELSE ActivateGrip := TRUE; END_IF
    ELSIF fsStep = 3 THEN
      IF UpLimitSwitch THEN fsDone := TRUE; ELSE MoveUp := TRUE; END_IF
    ELSIF fsStep = 4 THEN
      IF RightLimitSwitch THEN fsDone := TRUE; ELSE MoveRight := TRUE; END_IF
    ELSIF fsStep = 5 THEN
      IF DownLimitSwitch THEN fsDone := TRUE; ELSE MoveDown := TRUE; END_IF
    ELSIF fsStep = 6 THEN
      IF ReleaseLimitSwitch THEN fsDone := TRUE; ELSE ActivateRelease := TRUE; END_IF
    ELSIF fsStep = 7 THEN
      IF UpLimitSwitch THEN fsDone := TRUE; ELSE MoveUp := TRUE; END_IF
    ELSE
      IF LeftLimitSwitch THEN fsDone := TRUE; ELSE MoveLeft := TRUE; END_IF
    END_IF

    IF NOT fsDone THEN
      (* 本拍动作还没走完：停在当前步，本拍只输出这一个动作 *)
      guard := 8;
    ELSIF modeNow = 4 THEN
      (* R4 连续：本步一完成当拍就进入下一步，第 8 步之后回到第 1 步 *)
      fsStep := fsStep + 1;
      IF fsStep > 8 THEN
        fsStep := 1;
      END_IF
    ELSIF modeNow = 3 THEN
      (* R3 单循环：第 8 步（回左）完成即整轮结束，停在左上等下一次启动 *)
      IF fsStep >= 8 THEN
        fsActive := FALSE;
        fsStep := 0;
      ELSE
        fsStep := fsStep + 1;
      END_IF
    ELSE
      (* R2 单步：一个动作做完就停，等下一次 Start 确认 *)
      fsActive := FALSE;
      fsStep := fsStep + 1;
      IF fsStep > 8 THEN
        fsStep := 1;
      END_IF
    END_IF
  END_WHILE
END_IF

END_FUNCTION_BLOCK
