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
    prevAbortBtn : BOOL := FALSE;
    risingStart  : BOOL;
END_VAR

(* Rising edge of start *)
risingStart := startBtn AND NOT prevStartBtn;

(* New start overrides abort to begin fresh batch *)
IF risingStart THEN
    elapsed := 0;
    timeout := FALSE;
    phase   := 1;
(* Abort has priority during normal operation (phases 1/2/3/0) *)
ELSIF abortBtn THEN
    phase := 9;
ELSE
    (* Normal operation *)
    IF phase = 1 THEN
        elapsed := elapsed + 1;
        IF pv >= setpoint THEN
            phase := 2;
        END_IF
    ELSIF phase = 2 THEN
        elapsed := elapsed + 1;
        IF elapsed >= maxDuration THEN
            timeout := TRUE;
            phase   := 3;
        END_IF
    END_IF
    (* Phases 0 and 3: wait for start *)
END_IF

(* Update edge‑detection history *)
prevStartBtn := startBtn;
prevAbortBtn := abortBtn;

END_FUNCTION_BLOCK