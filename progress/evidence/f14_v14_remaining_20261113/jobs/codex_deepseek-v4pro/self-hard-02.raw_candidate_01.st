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
    localPrevStart : BOOL;
    localPrevPhase : INT;
    localPrevElapsed : INT;
    localPrevTimeout : BOOL;
    localRising : BOOL;
END_VAR

(* CONTRACT_RULES [] *)

(* ENGINEERING_CONTRACT
   - rising(startBtn): activated only when !abort; sets (phase, elapsed, timeout)=(1,0,FALSE).
   - abortBtn: highest same-scan priority; forces phase=9 and freezes elapsed/timeout.
   - running count: previous phase=1/2 increments elapsed by exactly 1 before phase/timeout evaluation.
   - timeout boundary: when elapsed >= maxDuration on this scan, set timeout=TRUE and phase=3.
   - heating boundary: not timed out, previous phase=1 and pv>=setpoint -> phase=2; phase=2 is retained.
   - frozen states: phase=0/3/9 retain phase, elapsed, and timeout until valid start or abort.
   - units: elapsed and maxDuration are integer scan counts; no TIME/LTIME or timer used.
   - start edge is consumed every scan, including same-scan abort, by updating localPrevStart.
*)

localRising := startBtn AND NOT localPrevStart;
localPrevPhase := phase;
localPrevElapsed := elapsed;
localPrevTimeout := timeout;

IF abortBtn THEN
    phase := 9;
    elapsed := localPrevElapsed;
    timeout := localPrevTimeout;
ELSIF localRising THEN
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSIF (localPrevPhase = 1) OR (localPrevPhase = 2) THEN
    elapsed := localPrevElapsed + 1;

    IF elapsed >= maxDuration THEN
        timeout := TRUE;
        phase := 3;
    ELSIF (localPrevPhase = 1) AND (pv >= setpoint) THEN
        timeout := FALSE;
        phase := 2;
    ELSIF localPrevPhase = 2 THEN
        timeout := FALSE;
        phase := 2;
    ELSE
        timeout := FALSE;
        phase := 1;
    END_IF
ELSE
    phase := localPrevPhase;
    elapsed := localPrevElapsed;
    timeout := localPrevTimeout;
END_IF

localPrevStart := startBtn;

END_FUNCTION_BLOCK