(* ENGINEERING_CONTRACT
   - phase: 0 idle initial; new start & !abort -> 1; in running, elapsed<maxDuration and (prevPhase=2 or pv>=setpoint) -> 2, else 1; elapsed>=maxDuration -> 3; abort -> 9. Priority abort > start edge > run count (PUB002-006).
   - elapsed: increment exactly once per scan when !abort, !startEdge, prevPhase=1/2; reset 0 on new start; freeze otherwise.
   - timeout: set TRUE exactly when running scan counted reaches maxDuration; reset FALSE on new start; freeze on abort/completion/idle.
   - start rising edge recorded first and consumed even if abort same scan; restart requires release/press.
   - maxDuration positive scan count; comparison >=. Boundaries: counts scan after start not counted.
*)
FUNCTION_BLOCK FB
VAR
    prevStartBtn : BOOL := FALSE;
    prevPhase : INT := 0;
    prevElapsed : INT := 0;
    prevTimeout : BOOL := FALSE;
    startEdge : BOOL;
END_VAR

(* Record startBtn rising edge before priority processing; consumed even if abort *)
startEdge := startBtn AND NOT prevStartBtn;

IF abortBtn THEN
    (* Abort has highest priority: enter phase 9 and freeze elapsed/timeout *)
    phase := 9;
    elapsed := prevElapsed;
    timeout := prevTimeout;
ELSIF startEdge THEN
    (* New valid start with no abort: reset batch and do not count this scan *)
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSE
    (* No abort and no new start edge *)
    IF (prevPhase = 1) OR (prevPhase = 2) THEN
        (* Running state: count exactly one scan *)
        elapsed := prevElapsed + 1;

        IF elapsed >= maxDuration THEN
            (* Timeout has priority over temperature threshold *)
            timeout := TRUE;
            phase := 3;
        ELSE
            timeout := FALSE;
            IF (prevPhase = 2) OR (pv >= setpoint) THEN
                phase := 2;
            ELSE
                phase := 1;
            END_IF;
        END_IF;
    ELSE
        (* Idle, complete, or aborted: hold state *)
        phase := prevPhase;
        elapsed := prevElapsed;
        timeout := prevTimeout;
    END_IF;
END_IF;

(* Update previous-cycle memory *)
prevStartBtn := startBtn;
prevPhase := phase;
prevElapsed := elapsed;
prevTimeout := timeout;

(* CONTRACT_RULES [] *)
END_FUNCTION_BLOCK