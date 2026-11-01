FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    resetBtn : BOOL;
    doneSensor : BOOL;
    targetVol : REAL;
    flowVol : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;
    fillsToday : INT;
END_VAR
VAR
    resetEdgeInputPrev : BOOL;
    startEdgeInputPrev : BOOL;
    startEdge : BOOL;
    resetEdge : BOOL;
    accumulated : REAL;
    filling : BOOL;
    waitAck : BOOL;
END_VAR

startEdge := startBtn AND NOT startEdgeInputPrev;
startEdgeInputPrev := startBtn;
resetEdge := resetBtn AND NOT resetEdgeInputPrev;
resetEdgeInputPrev := resetBtn;

(* 复位最高优先级：清零计数、关阀 *)
IF resetEdge THEN
    fillsToday := 0;
    valveOpen := FALSE;
    filling := FALSE;
    waitAck := FALSE;
    accumulated := 0.0;
ELSE
    (* 运途中重复按启动无效：只在非灌装、非待确认时接受 *)
    (* 待确认期间再按启动：允许直接开灌下一瓶，上一瓶未确认就不计数了 *)
    IF startEdge AND waitAck THEN
        waitAck := FALSE;
    END_IF
    IF startEdge AND NOT filling THEN
        filling := TRUE;
        valveOpen := TRUE;
        accumulated := 0.0;
    END_IF

    IF filling THEN
        accumulated := accumulated + flowVol;
        (* 达到或超过目标立即关阀，用 >= 而不是 > *)
        IF accumulated >= targetVol THEN
            valveOpen := FALSE;
            filling := FALSE;
            waitAck := TRUE;
        END_IF
    END_IF

    (* 计数只在满瓶确认之后发生一次 *)
    IF waitAck AND doneSensor THEN
        fillsToday := fillsToday + 1;
        waitAck := FALSE;
    END_IF
END_IF
END_FUNCTION_BLOCK
