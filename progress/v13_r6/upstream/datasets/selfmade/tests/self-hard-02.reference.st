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
    startPrev : BOOL;
    startEdge : BOOL;
END_VAR

(* phase: 0=空闲 1=升温 2=保温 3=完成（超时） 9=已中止
   本拍的判定顺序固定为：中止 > 新启动沿 > 运行计数。
   中止只改阶段号，不清计数也不清超时标志；同一拍出现的启动沿
   因为 startPrev 已经跟着更新而被"消耗"掉，不会在下一拍再生效，
   必须松开再按一次才算新的启动。 *)
startEdge := startBtn AND NOT startPrev;
startPrev := startBtn;

IF abortBtn THEN
    (* 中止优先级最高：任何阶段按下都立即进 9，计数与超时标志保持不动 *)
    phase := 9;
ELSIF startEdge THEN
    (* 新批次：阶段回 1，计数与超时清零；启动这一拍不计数 *)
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSIF phase = 1 OR phase = 2 THEN
    (* 计时靠扫描周期自累加，不依赖外部时钟：先加 1，再判超时 *)
    elapsed := elapsed + 1;
    IF elapsed >= maxDuration THEN
        (* 超时优先于升温达标：同一拍既到时限又到设定值时进完成态 *)
        timeout := TRUE;
        phase := 3;
    ELSIF phase = 1 AND pv >= setpoint THEN
        phase := 2;
    END_IF
END_IF
END_FUNCTION_BLOCK
