(* ENGINEERING_CONTRACT *)
(*
  Gate FSM: 4 states (IDLE/OPENING/CLOSING/FAULT), obstacle safety interlock.
  Priority order (highest first):
  1. Obstacle → stop both, enter FAULT, set errorFlag (same scan).
  2. FAULT → motors held FALSE; reset only on risingBoth when !obstacle.
  3. OPENING/CLOSING → motors set by state; own-limit stops and returns IDLE.
  4. IDLE → rising edge start on single valid button; simultaneous → no start.
  Motors always mutually exclusive (only one direction active at a time).
  Latched outputs: errorFlag (hold_until_reset via risingBoth).
*)
TYPE GateState :
(
    IDLE    := 0,
    OPENING := 1,
    CLOSING := 2,
    FAULT   := 3
);
END_TYPE;

FUNCTION_BLOCK FB
VAR_INPUT
    openBtn    : BOOL;
    closeBtn   : BOOL;
    openLimit  : BOOL;
    closeLimit : BOOL;
    obstacle   : BOOL;
END_VAR

VAR_OUTPUT
    motorUp    : BOOL;
    motorDown  : BOOL;
    errorFlag  : BOOL;
END_VAR

VAR
    state         : GateState := IDLE;
    prevOpenBtn   : BOOL := FALSE;
    prevCloseBtn  : BOOL := FALSE;
    prevMotorUp   : BOOL := FALSE;
    prevMotorDown : BOOL := FALSE;
    prevErrorFlag : BOOL := FALSE;
END_VAR

VAR
    risingOpen  : BOOL;
    risingClose : BOOL;
    risingBoth  : BOOL;
END_VAR

risingOpen  := openBtn  AND NOT prevOpenBtn;
risingClose := closeBtn AND NOT prevCloseBtn;
risingBoth  := openBtn AND closeBtn AND NOT prevOpenBtn AND NOT prevCloseBtn;

IF obstacle THEN
    motorUp   := FALSE;
    motorDown := FALSE;
    errorFlag := TRUE;
    state     := FAULT;
ELSE
    errorFlag := FALSE;

    IF state = FAULT THEN
        motorUp   := FALSE;
        motorDown := FALSE;
        IF risingBoth THEN
            state := IDLE;
        END_IF;

    ELSIF state = IDLE THEN
        motorUp   := FALSE;
        motorDown := FALSE;
        IF risingOpen AND NOT closeBtn AND NOT openLimit THEN
            state := OPENING;
        ELSIF risingClose AND NOT openBtn AND NOT closeLimit THEN
            state := CLOSING;
        END_IF;

    ELSIF state = OPENING THEN
        motorUp   := TRUE;
        motorDown := FALSE;
        IF openLimit THEN
            motorUp := FALSE;
            state   := IDLE;
        END_IF;

    ELSIF state = CLOSING THEN
        motorUp   := FALSE;
        motorDown := TRUE;
        IF closeLimit THEN
            motorDown := FALSE;
            state     := IDLE;
        END_IF;
    END_IF;
END_IF;

prevOpenBtn   := openBtn;
prevCloseBtn  := closeBtn;
prevMotorUp   := motorUp;
prevMotorDown := motorDown;
prevErrorFlag := errorFlag;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)