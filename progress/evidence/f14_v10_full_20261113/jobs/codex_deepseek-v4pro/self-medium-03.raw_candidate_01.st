FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT
   motorUp: IDLE + rising(openBtn) + !closeBtn + !openLimit starts same scan;
   retained in OPENING until openLimit, limit scan returns IDLE and stops same scan.
   motorDown: symmetric with closeBtn/closeLimit.
   errorFlag: any obstacle in any state sets it same scan and stops both directions.
   FAULT retains errorFlag; clear only when !obstacle and rising(openBtn AND closeBtn).
   Reset scan returns IDLE with both motors stopped.
   Priority: obstacle before limit/motion/reset; both buttons pressed together do not start.
*)
(* CONTRACT_RULES [] *)
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
    state : SINT := 0; (* 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT *)
    prevOpenBtn : BOOL := FALSE;
    prevCloseBtn : BOOL := FALSE;
    tmp_risingOpen : BOOL;
    tmp_risingClose : BOOL;
    tmp_risingBoth : BOOL;
END_VAR

motorUp := FALSE;
motorDown := FALSE;
errorFlag := FALSE;

tmp_risingOpen := openBtn AND NOT prevOpenBtn;
tmp_risingClose := closeBtn AND NOT prevCloseBtn;
tmp_risingBoth := openBtn AND closeBtn AND NOT (prevOpenBtn AND prevCloseBtn);

IF obstacle THEN
    errorFlag := TRUE;
    state := 3;
ELSIF state = 3 THEN
    IF tmp_risingBoth THEN
        errorFlag := FALSE;
        state := 0;
    ELSE
        errorFlag := TRUE;
        state := 3;
    END_IF;
ELSIF state = 0 THEN
    IF tmp_risingOpen AND NOT closeBtn AND NOT openLimit THEN
        motorUp := TRUE;
        state := 1;
    ELSIF tmp_risingClose AND NOT openBtn AND NOT closeLimit THEN
        motorDown := TRUE;
        state := 2;
    ELSE
        state := 0;
    END_IF;
ELSIF state = 1 THEN
    IF openLimit THEN
        state := 0;
    ELSE
        motorUp := TRUE;
        state := 1;
    END_IF;
ELSIF state = 2 THEN
    IF closeLimit THEN
        state := 0;
    ELSE
        motorDown := TRUE;
        state := 2;
    END_IF;
END_IF;

prevOpenBtn := openBtn;
prevCloseBtn := closeBtn;
END_FUNCTION_BLOCK