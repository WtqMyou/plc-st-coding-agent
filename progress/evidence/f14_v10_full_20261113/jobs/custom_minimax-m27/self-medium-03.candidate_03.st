Looking at the functional failures, the issue is clear from the replay: `motorUp` is not being set in the same scan as the rising edge triggers the state transition. The motor assignments need to occur after all state transitions, not interleaved within each branch.

```st
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
    state         : INT := 0;
    prevOpenBtn   : BOOL := FALSE;
    prevCloseBtn  : BOOL := FALSE;
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
    state     := 3;
    errorFlag := TRUE;
ELSE
    errorFlag := FALSE;

    IF state = 3 THEN
        IF risingBoth THEN
            state := 0;
        END_IF;

    ELSIF state = 0 THEN
        IF risingOpen AND NOT closeBtn AND NOT openLimit THEN
            state := 1;
        ELSIF risingClose AND NOT openBtn AND NOT closeLimit THEN
            state := 2;
        END_IF;

    ELSIF state = 1 THEN
        IF openLimit THEN
            state := 0;
        END_IF;

    ELSIF state = 2 THEN
        IF closeLimit THEN
            state := 0;
        END_IF;
    END_IF;
END_IF;

CASE state OF
    0: motorUp := FALSE; motorDown := FALSE;
    1: motorUp := TRUE;  motorDown := FALSE;
    2: motorUp := FALSE; motorDown := TRUE;
    3: motorUp := FALSE; motorDown := FALSE;
END_CASE;

prevOpenBtn  := openBtn;
prevCloseBtn := closeBtn;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)