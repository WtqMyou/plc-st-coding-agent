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
    resetEdgeInputPrev : BOOL;
    resetEdge : BOOL;
    latchReset : BOOL;
END_VAR

(* 复位只取上升沿：按住不放只生效一次 *)
resetEdge := resetBtn AND NOT resetEdgeInputPrev;
resetEdgeInputPrev := resetBtn;
latchReset := resetEdge;

(* 报警自保持：置位优先于复位，且复位条件只在上升沿成立一个周期 *)
IF tankLevel >= 85.0 AND NOT latchReset THEN
    alarmHigh := TRUE;
END_IF
IF latchReset THEN
    alarmHigh := FALSE;
END_IF
IF tankLevel <= 15.0 AND NOT latchReset THEN
    alarmLow := TRUE;
END_IF
IF latchReset THEN
    alarmLow := FALSE;
END_IF

(* 联锁：任一报警存在都不得进料 *)
pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow
           AND tankLevel < 85.0 AND tankLevel >= 15.0;

(* 出口阀在低液位报警时强制关闭 *)
outletValveOpen := NOT alarmLow AND tankLevel > 15.0;
END_FUNCTION_BLOCK
