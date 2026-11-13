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
    prevStartBtn : BOOL;
    tmpStartRising : BOOL;
    tmpPrevPhase : INT;
    tmpPrevElapsed : INT;
    tmpPrevTimeout : BOOL;
    tmpIsRunPrev : BOOL;
    tmpNewElapsed : INT;
END_VAR

(* ENGINEERING_CONTRACT
   phase: 0 idle, 1 heating, 2 soaking, 3 done, 9 aborted.
   Activation: phase=1 on start rising without abort; phase=2 when previous run phase is 1 and pv>=setpoint before timeout; phase=3 when elapsed>=maxDuration; phase=9 on abort.
   Retention: phase 3/9 hold until new start or abort; start resets to 1 and clears elapsed/timeout; abort from 3/9 preserves elapsed/timeout.
   elapsed: counts scans when previous phase is 1 or 2 and no abort/start rising. Reset to 0 on start; frozen in 3/9; frozen on abort.
   timeout: set TRUE when new elapsed>=maxDuration (scan count); cleared on start; frozen on abort; otherwise equals timeout condition.
   Priority: abort > start rising > running count; same-scan start edge consumed even under abort.
   Units: elapsed/maxDuration in scan counts, INT; no timer used.
*)

(* CONTRACT_RULES [] *)

tmpStartRising := startBtn AND NOT prevStartBtn;
tmpPrevPhase := phase;
tmpPrevElapsed := elapsed;
tmpPrevTimeout := timeout;
tmpIsRunPrev := (tmpPrevPhase = 1) OR (tmpPrevPhase = 2);

IF abortBtn THEN
    phase := 9;
    elapsed := tmpPrevElapsed;
    timeout := tmpPrevTimeout;
ELSIF tmpStartRising THEN
    phase := 1;
    elapsed := 0;
    timeout := FALSE;
ELSE
    IF tmpIsRunPrev THEN
        tmpNewElapsed := tmpPrevElapsed + 1;
        elapsed := tmpNewElapsed;
        IF tmpNewElapsed >= maxDuration THEN
            timeout := TRUE;
            phase := 3;
        ELSE
            timeout := FALSE;
            IF tmpPrevPhase = 2 THEN
                phase := 2;
            ELSE
                IF pv >= setpoint THEN
                    phase := 2;
                ELSE
                    phase := 1;
                END_IF;
            END_IF;
        END_IF;
    ELSE
        phase := tmpPrevPhase;
        elapsed := tmpPrevElapsed;
        timeout := tmpPrevTimeout;
    END_IF;
END_IF;

prevStartBtn := startBtn;
END_FUNCTION_BLOCK