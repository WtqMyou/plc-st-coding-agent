(* ENGINEERING_CONTRACT
   State IDLE/OPENING/CLOSING/FAULT retained in FB; initial IDLE, all previous inputs/outputs FALSE.
   motorUp: activates on IDLE legal open edge, holds while no obstacle and no openLimit; stops at limit/obstacle/fault.
   motorDown: symmetric close handling, holds while no obstacle and no closeLimit.
   errorFlag: set by obstacle any scan; latched until bothBTN rising edge and no obstacle; obstacle overrides reset.
   prev* memory updated after outputs; BOOL units, initial prev FALSE.
*)
(* CONTRACT_RULES [] *)
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
    state : INT := 0; (* 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT *)
    prevOpenBtn : BOOL := FALSE;
    prevCloseBtn : BOOL := FALSE;
    prevBothBtn : BOOL := FALSE;
    prevMotorUp : BOOL := FALSE;
    prevMotorDown : BOOL := FALSE;
    prevErrorFlag : BOOL := FALSE;
    prevObstacle : BOOL := FALSE;
    risingOpen : BOOL;
    risingClose : BOOL;
    risingBoth : BOOL;
END_VAR

risingOpen := openBtn AND (NOT prevOpenBtn);
risingClose := closeBtn AND (NOT prevCloseBtn);
risingBoth := (openBtn AND closeBtn) AND (NOT prevBothBtn);

motorUp := (NOT obstacle) AND (NOT openLimit) AND
           (prevMotorUp OR
            ((NOT prevMotorUp) AND (NOT prevMotorDown) AND
             (NOT prevErrorFlag) AND risingOpen AND (NOT closeBtn)));

motorDown := (NOT obstacle) AND (NOT closeLimit) AND
             (prevMotorDown OR
              ((NOT prevMotorUp) AND (NOT prevMotorDown) AND
               (NOT prevErrorFlag) AND risingClose AND (NOT openBtn)));

errorFlag := obstacle OR (prevErrorFlag AND (NOT risingBoth));

IF obstacle THEN
    state := 3;
ELSIF state = 3 THEN
    IF risingBoth THEN
        state := 0;
    ELSE
        state := 3;
    END_IF;
ELSE
    IF motorUp THEN
        state := 1;
    ELSIF motorDown THEN
        state := 2;
    ELSE
        state := 0;
    END_IF;
END_IF;

prevOpenBtn := openBtn;
prevCloseBtn := closeBtn;
prevBothBtn := openBtn AND closeBtn;
prevMotorUp := motorUp;
prevMotorDown := motorDown;
prevErrorFlag := errorFlag;
prevObstacle := obstacle;

END_FUNCTION_BLOCK