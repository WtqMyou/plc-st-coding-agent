FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    abortBtn    : BOOL;
    setpoint    : REAL;
    pv          : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed : INT;
    phase   : INT;
    timeout : BOOL;
END_VAR
VAR
    prevStartBtn : BOOL := FALSE;
    prevPhase    : INT  := 0;
    prevElapsed  : INT  := 0;
    prevTimeout  : BOOL := FALSE;
END_VAR

(* temporary variable for rising edge detection *)
VAR
    risingStart : BOOL;
END_VAR

(* detect rising edge of start button *)
risingStart := startBtn AND NOT prevStartBtn;

(* abort has the highest priority *)
IF abortBtn THEN
    phase   := 9;
    elapsed := prevElapsed;
    timeout := prevTimeout;
    (* the start‑button rising edge in this scan is ignored *)
ELSE
    (* new batch start on rising edge of start button *)
    IF risingStart THEN
        phase   := 1;
        elapsed := 0;
        timeout := FALSE;
    ELSE
        (* no abort, no new start: update based on previous state *)
        IF (prevPhase = 1) OR (prevPhase = 2) THEN
            (* running phase – increment scan counter *)
            elapsed := prevElapsed + 1;

            (* check for timeout *)
            IF elapsed >= maxDuration THEN
                timeout := TRUE;
                phase   := 3;                (* completed due to timeout *)
            ELSE
                (* no timeout – decide heating or holding according to temperature *)
                IF prevPhase = 1 THEN
                    IF pv >= setpoint THEN
                        phase := 2;          (* temperature reached → hold *)
                    ELSE
                        phase := 1;          (* still heating *)
                    END_IF;
                ELSE                           (* prevPhase = 2 *)
                    phase := 2;              (* remain in holding *)
                END_IF;
                timeout := prevTimeout;       (* should be FALSE *)
            END_IF;
        ELSE
            (* previous scan was not a running phase – keep state unchanged *)
            phase   := prevPhase;
            elapsed := prevElapsed;
            timeout := prevTimeout;
        END_IF;
    END_IF;
END_IF;

(* update memory for the next scan *)
prevStartBtn := startBtn;
prevPhase    := phase;
prevElapsed  := elapsed;
prevTimeout  := timeout;

END_FUNCTION_BLOCK