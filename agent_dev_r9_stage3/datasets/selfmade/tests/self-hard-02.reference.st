FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    abortBtn : BOOL;
    setpoint : REAL;
    pv : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed : INT;
    phase : INT;
    timeout : BOOL;
END_VAR
VAR
    startEdgeInputPrev : BOOL;
    startEdge : BOOL;
END_VAR

(* phase: 0=空闲 1=升温 2=保温 9=中止/超时结束 *)
startEdge := startBtn AND NOT startEdgeInputPrev;
startEdgeInputPrev := startBtn;

IF startEdge THEN
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSIF abortBtn THEN
    phase := 9;
ELSIF phase = 1 OR phase = 2 THEN
    (* 计时靠扫描周期自累加，不依赖外部时钟 *)
    elapsed := elapsed + 1;
    (* 阶段推进：升温到设定值转保温；已是保温则保持 *)
    IF phase = 1 AND pv >= setpoint THEN
        phase := 2;
    END_IF
    (* 超时判定放在阶段推进之后，保证"到设定值"的优先级低于"超时停机" *)
    IF elapsed >= maxDuration THEN
        timeout := TRUE;
        phase := 9;
    END_IF
END_IF
END_FUNCTION_BLOCK
