(*
ENGINEERING_CONTRACT
- motorUp: start on IDLE open-button rising edge with closeBtn FALSE and openLimit FALSE; retain while moving; stop on obstacle/openLimit/fault/clear scan.
- motorDown: symmetric with openBtn FALSE and closeLimit FALSE; mutually exclusive with motorUp.
- errorFlag: set by any obstacle; latched; cleared only by no-obstacle rising(openBtn AND closeBtn); clear scan keeps motors off.
- State: initial IDLE; OPENING/CLOSING track active motion; FAULT latches; clear returns IDLE. Conflicting dual-button edge starts neither motor.
- Same-scan priority: obstacle/fault dominates limit, motion, and reset; outputs are evaluated from the current sampled inputs.
*)
(* CONTRACT_RULES [] *)

TYPE FB_STATE : (IDLE, OPENING, CLOSING, FAULT); END_TYPE;

FUNCTION_BLOCK FB
VAR_INPUT
    openBtn : BOOL;
    closeBtn : BOOL;
    openLimit : BOOL;
    closeLimit : BOOL;
    obstacle : BOOL;
END_VAR
VAR_OUTPUT
    motorUp : BOOL;
    motorDown : BOOL;
    errorFlag : BOOL;
END_VAR
VAR
    state : FB_STATE := IDLE;
    prevOpenBtn : BOOL := FALSE;
    prevCloseBtn : BOOL := FALSE;
    prevMotorUp : BOOL := FALSE;
    prevMotorDown : BOOL := FALSE;
    prevErrorFlag : BOOL := FALSE;
    local_risingOpen : BOOL := FALSE;
    local_risingClose : BOOL := FALSE;
    local_risingBoth : BOOL := FALSE;
    local_errNow : BOOL := FALSE;
    local_startUp : BOOL := FALSE;
    local_startDown : BOOL := FALSE;
    local_runUp : BOOL := FALSE;
    local_runDown : BOOL := FALSE;
END_VAR

local_risingOpen := openBtn AND NOT prevOpenBtn;
local_risingClose := closeBtn AND NOT prevCloseBtn;
local_risingBoth := openBtn AND closeBtn AND NOT (prevOpenBtn AND prevCloseBtn);

local_errNow := obstacle OR (prevErrorFlag AND NOT local_risingBoth);

IF local_errNow THEN
    errorFlag := TRUE;
    motorUp := FALSE;
    motorDown := FALSE;
    state := FAULT;
ELSE
    local_startUp := NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag
        AND NOT obstacle AND local_risingOpen AND NOT closeBtn AND NOT openLimit;
    local_startDown := NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag
        AND NOT obstacle AND local_risingClose AND NOT openBtn AND NOT closeLimit;
    local_runUp := prevMotorUp AND NOT prevErrorFlag AND NOT obstacle AND NOT openLimit;
    local_runDown := prevMotorDown AND NOT prevErrorFlag AND NOT obstacle AND NOT closeLimit;

    motorUp := local_startUp OR local_runUp;
    motorDown := local_startDown OR local_runDown;
    errorFlag := FALSE;

    IF motorUp THEN
        state := OPENING;
    ELSIF motorDown THEN
        state := CLOSING;
    ELSE
        state := IDLE;
    END_IF;
END_IF;

prevOpenBtn := openBtn;
prevCloseBtn := closeBtn;
prevMotorUp := motorUp;
prevMotorDown := motorDown;
prevErrorFlag := errorFlag;

END_FUNCTION_BLOCK