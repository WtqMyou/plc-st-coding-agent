FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT
   Output group motorUp/motorDown/errorFlag:
   - motorUp activation: state=OPENING while !obstacle and !openLimit (PUB003, PUB010, PUB012).
   - motorDown activation: state=CLOSING while !obstacle and !closeLimit (PUB003, PUB011, PUB013).
   - Retention: motion continues after button release until own limit, obstacle, or FAULT reset (PUB003, PUB012, PUB013).
   - Deactivation: own limit stops and returns to IDLE same scan; obstacle or FAULT stops both (PUB004-PUB006).
   - Same-scan priority: obstacle > limit/motion/reset; reset only returns to IDLE with motors stopped (PUB005, PUB007).
   - errorFlag activation: any obstacle, latched in FAULT (PUB004, PUB006).
   - errorFlag reset: only !obstacle and rising(openBtn AND closeBtn) (PUB007); no release-while-held auto reset.
   - Units/boundaries: BOOL signals; no timers; S1-S14 motor exclusion and latching contracts.
*)
(* CONTRACT_RULES [] *)
VAR_INPUT
    openBtn: BOOL;
    closeBtn: BOOL;
    openLimit: BOOL;
    closeLimit: BOOL;
    obstacle: BOOL;
END_VAR
VAR_OUTPUT
    motorUp: BOOL;
    motorDown: BOOL;
    errorFlag: BOOL;
END_VAR
VAR
    state: INT := 0; (* 0: IDLE, 1: OPENING, 2: CLOSING, 3: FAULT *)
    latchedFault: BOOL := FALSE;
    prevOpenBtn: BOOL := FALSE;
    prevCloseBtn: BOOL := FALSE;
    tmp_rOpen: BOOL;
    tmp_rClose: BOOL;
    tmp_rBoth: BOOL;
    tmp_state: INT;
    tmp_fault: BOOL;
    tmp_up: BOOL;
    tmp_down: BOOL;
END_VAR

tmp_rOpen := openBtn AND NOT prevOpenBtn;
tmp_rClose := closeBtn AND NOT prevCloseBtn;
tmp_rBoth := openBtn AND closeBtn AND NOT (prevOpenBtn AND prevCloseBtn);

tmp_state := state;
tmp_fault := latchedFault;
tmp_up := FALSE;
tmp_down := FALSE;

IF obstacle THEN
    tmp_state := 3;
    tmp_fault := TRUE;
ELSE
    IF state = 3 THEN
        IF tmp_rBoth THEN
            tmp_state := 0;
            tmp_fault := FALSE;
        END_IF
    ELSIF state = 0 THEN
        IF tmp_rOpen AND NOT closeBtn AND NOT openLimit THEN
            tmp_state := 1;
            tmp_up := TRUE;
        ELSIF tmp_rClose AND NOT openBtn AND NOT closeLimit THEN
            tmp_state := 2;
            tmp_down := TRUE;
        END_IF
    ELSIF state = 1 THEN
        IF openLimit THEN
            tmp_state := 0;
        ELSE
            tmp_up := TRUE;
        END_IF
    ELSIF state = 2 THEN
        IF closeLimit THEN
            tmp_state := 0;
        ELSE
            tmp_down := TRUE;
        END_IF
    END_IF
END_IF

state := tmp_state;
latchedFault := tmp_fault;
motorUp := tmp_up;
motorDown := tmp_down;
errorFlag := latchedFault;

prevOpenBtn := openBtn;
prevCloseBtn := closeBtn;

END_FUNCTION_BLOCK