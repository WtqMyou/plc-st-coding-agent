FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel : REAL;
    outletFlow : REAL;
    inletPermit : BOOL;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun : BOOL;
    alarmHigh : BOOL;
    alarmLow : BOOL;
    outletValveOpen : BOOL;
END_VAR
VAR
    resetPrev : BOOL;
    resetEdge : BOOL;
    latchReset : BOOL;
END_VAR

(* 复位只取上升沿：按住不放只生效一次。
   边沿必须用独立的 prev 变量记忆上一拍电平，不能写成
   "resetEdge := resetBtn AND NOT resetEdge" —— 那是拿输出当记忆，
   按钮按住时 resetEdge 会振成 真/假/真/假，每两拍就多一个假边沿。 *)
resetEdge := resetBtn AND NOT resetPrev;
resetPrev := resetBtn;
latchReset := resetEdge;

(* 报警自保持：置位优先于复位，且复位条件只在上升沿成立一个周期 *)
(* 置位**不受复位抑制**：报警条件是硬联锁，按下复位不能让它少报一拍。
   复位只在"条件已经消失"时才允许清除（见下面的 gate），两条合起来
   才等价于第 5 条"报警优先于复位"。 *)
IF tankLevel >= 85.0 THEN
    alarmHigh := TRUE;
END_IF
(* 复位只在**条件已经消失**时生效：否则复位当拍会出现
   "液位仍 <= 15 但 alarmLow 已清、出口阀随即打开"的空窗期，
   直接违反"报警优先于复位"这一条。这个洞是模型检查找出来的，
   用例表当时是全绿的。 *)
IF latchReset AND tankLevel < 85.0 THEN
    alarmHigh := FALSE;
END_IF
IF tankLevel <= 15.0 THEN
    alarmLow := TRUE;
END_IF
IF latchReset AND tankLevel > 15.0 THEN
    alarmLow := FALSE;
END_IF

(* 联锁：任一报警存在都不得进料 *)
pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow
           AND tankLevel < 85.0 AND tankLevel >= 15.0;

(* 出口阀在低液位报警时强制关闭 *)
outletValveOpen := NOT alarmLow;
END_FUNCTION_BLOCK
