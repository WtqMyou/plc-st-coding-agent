(* ENGINEERING_CONTRACT
   - Outputs: phase, elapsed, timeout; initial (0,0,FALSE).
   - Priority: abort > new start edge > run counting (PUB002-006).
   - abortBtn TRUE: phase=9, elapsed/timeout hold previous values. Start edge consumed (PUB003, PUB005-006).
   - New start edge without abort: phase=1, elapsed=0, timeout=FALSE; start scan not counted (PUB004, PUB006).
   - Previous scan running (1 or 2), no abort, no start edge: increment elapsed by 1.
     If elapsed >= maxDuration: timeout=TRUE, phase=3 (timeout priority). Else phase=2 if pv>=setpoint or prevPhase=2, otherwise phase=1 (PUB005-006).
   - Phase 3 complete, phase 9 aborted: freeze elapsed, timeout, phase until new valid start or abort.
   - Unit: elapsed counts scans; maxDuration positive integer scan threshold; comparison >=.
*)
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
    prevStartBtn : BOOL := FALSE;
    prevPhase : INT := 0;
    prevElapsed : INT := 0;
    prevTimeout : BOOL := FALSE;
    startEdge : BOOL;
END_VAR

(* Record startBtn rising edge before priority processing; consumed even if abort *)
startEdge := startBtn AND NOT prevStartBtn;

IF abortBtn THEN
    (* Abort highest priority: enter phase 9 and freeze elapsed/timeout *)
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