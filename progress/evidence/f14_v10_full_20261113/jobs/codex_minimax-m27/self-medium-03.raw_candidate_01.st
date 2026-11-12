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
    state       : EState := IDLE;
    prev_openBtn   : BOOL := FALSE;
    prev_closeBtn  : BOOL := FALSE;
    prev_obstacle  : BOOL := FALSE;
    openRTrig      : R_TRIG;
    closeRTrig     : R_TRIG;
    dualRTrig      : R_TRIG;
END_VAR

(*
ENGINEERING_CONTRACT
===================
| Output/State | Activation          | Retention          | Reset/Deactivation        | Scan Priority | Units      |
|--------------|---------------------|--------------------|---------------------------|---------------|------------|
| motorUp      | IDLE+rising(openBtn)| Running continues  | obstacle/closeLimit/FAULT | Same-scan     | BOOL       |
| motorDown    | IDLE+rising(closeBtn)| Running continues | obstacle/openLimit/FAULT  | Same-scan     | BOOL       |
| errorFlag    | Any state+obstacle  | Latched in FAULT   | No obstacle+dualBtn rising| Highest      | BOOL       |
| state=FAULT  | Any state+obstacle  | Until dualBtn reset| No obstacle+dualBtn rising| Highest      | EState     |
| state=IDLE   | Power-on/limit/reset| Until openBtn/closeBtn rising | -                  | Default     | EState     |
PUB001: power-on IDLE
PUB002: init FALSE
PUB003: no obstacle IDLE start rules (openBtn edge, closeBtn=FALSE, not openLimit)
PUB004: no obstacle close start rules (closeBtn edge, openBtn=FALSE, not closeLimit)
PUB006: no dual-btn start
PUB007: same-scan motor command on start
PUB008: button release ignored during movement
PUB009: direction buttons ignored during movement
PUB010: limit stop same-scan
PUB011: opposite limit does not affect
PUB012: mutual exclusion always
PUB013: obstacle immediate both-stop + FAULT
PUB014: FAULT priority over limits/movement/reset
PUB017: errorFlag latched
PUB018: FAULT stop motors
PUB019: reset requires no obstacle + dualBtn from not-both to both
PUB020: cannot reset during obstacle
PUB021: cannot auto-reset on obstacle clear
PUB022: reset → IDLE
PUB023: reset same-scan both motors stop
PUB024: post-reset follow rule 1
*)
BEGIN
    openRTrig(CLK := openBtn);
    closeRTrig(CLK := closeBtn);
    dualRTrig(CLK := openBtn AND closeBtn);

    (* Priority 1: Obstacle → immediate stop + FAULT *)
    IF obstacle THEN
        motorUp   := FALSE;
        motorDown := FALSE;
        state     := FAULT;
        errorFlag := TRUE;
    ELSE
        CASE state OF
            IDLE:
                motorUp   := FALSE;
                motorDown := FALSE;

                (* Start opening *)
                IF openRTrig.Q AND NOT closeBtn AND NOT openLimit THEN
                    motorUp := TRUE;
                    state   := OPENING;
                (* Start closing *)
                ELSIF closeRTrig.Q AND NOT openBtn AND NOT closeLimit THEN
                    motorDown := TRUE;
                    state     := CLOSING;
                END_IF

            OPENING:
                motorUp   := TRUE;
                motorDown := FALSE;
                IF openLimit THEN
                    motorUp := FALSE;
                    state   := IDLE;
                END_IF

            CLOSING:
                motorUp   := FALSE;
                motorDown := TRUE;
                IF closeLimit THEN
                    motorDown := FALSE;
                    state     := IDLE;
                END_IF

            FAULT:
                motorUp   := FALSE;
                motorDown := FALSE;
                IF dualRTrig.Q THEN
                    errorFlag := FALSE;
                    state     := IDLE;
                END_IF
        END_CASE
    END_IF

    prev_openBtn  := openBtn;
    prev_closeBtn := closeBtn;
    prev_obstacle := obstacle;
END_FUNCTION_BLOCK

TYPE EState : (
    IDLE    := 0,
    OPENING := 1,
    CLOSING := 2,
    FAULT   := 3
) END_TYPE
END_TYPE

(* CONTRACT_RULES [] *)