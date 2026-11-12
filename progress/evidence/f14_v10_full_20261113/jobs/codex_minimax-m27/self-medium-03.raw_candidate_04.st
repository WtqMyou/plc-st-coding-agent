TYPE EState : 
    (
        IDLE    := 0,
        OPENING := 1,
        CLOSING := 2,
        FAULT   := 3
    )
END_TYPE

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
    state          : EState := IDLE;
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
| Output/State | Activation           | Retention           | Reset/Deactivation              | Scan Priority | Units   |
|--------------|----------------------|---------------------|----------------------------------|---------------|---------|
| motorUp      | IDLE+rising(openBtn) | Running continues   | obstacle/openLimit/FAULT         | Same-scan     | BOOL    |
| motorDown    | IDLE+rising(closeBtn)| Running continues   | obstacle/closeLimit/FAULT        | Same-scan     | BOOL    |
| errorFlag    | Any state+obstacle   | Latched in FAULT    | No obstacle+dualBtn rising edge  | Highest       | BOOL    |
| state=FAULT  | Any state+obstacle   | Until dualBtn reset | No obstacle+dualBtn rising edge  | Highest       | EState  |
| state=IDLE   | Power-on/limit/reset | Until rising edge   | -                                | Default       | EState  |
PUB001: power-on IDLE
PUB002: init FALSE
PUB003-005: no obstacle IDLE start (openBtn rising, closeBtn=FALSE, not openLimit)
PUB006: dual-btn does not start
PUB007: motor command same-scan on start
PUB008-009: button release / direction buttons ignored during movement
PUB010-011: limit stop same-scan, opposite limit irrelevant
PUB012: mutual exclusion always
PUB013-014: obstacle → both stop + FAULT (highest priority)
PUB017-018: errorFlag latched, motors stopped in FAULT
PUB019-021: reset requires no obstacle + dualBtn from not-both to both
PUB022-024: reset → IDLE, same-scan stop, then follow rule 1
*)

BEGIN
    openRTrig(CLK := openBtn);
    closeRTrig(CLK := closeBtn);
    dualRTrig(CLK := openBtn AND closeBtn);

    (* Priority 1: Obstacle → immediate both-stop + FAULT *)
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
                (* Start opening: rising edge of openBtn, closeBtn=FALSE, not at openLimit *)
                IF openRTrig.Q AND NOT closeBtn AND NOT openLimit THEN
                    motorUp := TRUE;
                    state   := OPENING;
                (* Start closing: rising edge of closeBtn, openBtn=FALSE, not at closeLimit *)
                ELSIF closeRTrig.Q AND NOT openBtn AND NOT closeLimit THEN
                    motorDown := TRUE;
                    state     := CLOSING;
                END_IF;

            OPENING:
                motorUp   := TRUE;
                motorDown := FALSE;
                IF openLimit THEN
                    motorUp := FALSE;
                    state   := IDLE;
                END_IF;

            CLOSING:
                motorUp   := FALSE;
                motorDown := TRUE;
                IF closeLimit THEN
                    motorDown := FALSE;
                    state     := IDLE;
                END_IF;

            FAULT:
                motorUp   := FALSE;
                motorDown := FALSE;
                IF dualRTrig.Q THEN
                    errorFlag := FALSE;
                    state     := IDLE;
                END_IF;
        END_CASE;
    END_IF;

    prev_openBtn  := openBtn;
    prev_closeBtn := closeBtn;
    prev_obstacle := obstacle;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)