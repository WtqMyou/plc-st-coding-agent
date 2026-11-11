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
    openBtnPrev    : BOOL := FALSE;
    closeBtnPrev   : BOOL := FALSE;
    combinedPrev   : BOOL := FALSE;
    prevMotorUp    : BOOL := FALSE;
    prevMotorDown  : BOOL := FALSE;
    prevErrorFlag  : BOOL := FALSE;
    state          : INT  := 0;   // 0=IDLE,1=OPENING,2=CLOSING,3=FAULT
END_VAR

(* Local auxiliary variables *)
VAR
    risingOpen     : BOOL;
    risingClose    : BOOL;
    risingCombined : BOOL;
    combinedNow    : BOOL;
    startOpen      : BOOL;
    startClose     : BOOL;
END_VAR

(* Detect combined button state *)
combinedNow    := openBtn AND closeBtn;

(* Detect rising edges *)
risingOpen     := openBtn   AND NOT openBtnPrev;
risingClose    := closeBtn  AND NOT closeBtnPrev;
risingCombined := combinedNow AND NOT combinedPrev;

(* Start conditions: new command from IDLE without fault and no obstacle *)
startOpen  := NOT prevMotorUp   AND NOT prevMotorDown   AND NOT prevErrorFlag
              AND risingOpen    AND NOT closeBtn AND NOT openLimit;

startClose := NOT prevMotorUp   AND NOT prevMotorDown   AND NOT prevErrorFlag
              AND risingClose   AND NOT openBtn  AND NOT closeLimit;

(* Motor commands according to S12 / S13 *)
motorUp   := NOT obstacle AND NOT openLimit
             AND (prevMotorUp OR startOpen);

motorDown := NOT obstacle AND NOT closeLimit
             AND (prevMotorDown OR startClose);

(* Error flag latch (S14) *)
errorFlag := obstacle OR (prevErrorFlag AND NOT risingCombined);

(* Optional state for external monitoring *)
IF errorFlag THEN
    state := 3;               (* FAULT *)
ELSIF motorUp THEN
    state := 1;               (* OPENING *)
ELSIF motorDown THEN
    state := 2;               (* CLOSING *)
ELSE
    state := 0;               (* IDLE *)
END_IF

(* Update previous values for next scan *)
openBtnPrev    := openBtn;
closeBtnPrev   := closeBtn;
combinedPrev   := combinedNow;
prevMotorUp    := motorUp;
prevMotorDown  := motorDown;
prevErrorFlag  := errorFlag;

END_FUNCTION_BLOCK