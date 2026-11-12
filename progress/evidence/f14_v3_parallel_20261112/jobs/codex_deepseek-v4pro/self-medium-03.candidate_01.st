FUNCTION_BLOCK FB
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
    prevOpenBtn: BOOL := FALSE;
    prevCloseBtn: BOOL := FALSE;
    prevMotorUp: BOOL := FALSE;
    prevMotorDown: BOOL := FALSE;
    prevErrorFlag: BOOL := FALSE;
    openRising: BOOL;
    closeRising: BOOL;
    bothRising: BOOL;
END_VAR

openRising := openBtn AND (NOT prevOpenBtn);
closeRising := closeBtn AND (NOT prevCloseBtn);
bothRising := (openBtn AND closeBtn) AND (NOT (prevOpenBtn AND prevCloseBtn));

motorUp := (NOT obstacle) AND (NOT openLimit) AND
    (prevMotorUp OR
     ((NOT prevMotorUp) AND (NOT prevMotorDown) AND (NOT prevErrorFlag) AND
      openRising AND (NOT closeBtn)));

motorDown := (NOT obstacle) AND (NOT closeLimit) AND
    (prevMotorDown OR
     ((NOT prevMotorUp) AND (NOT prevMotorDown) AND (NOT prevErrorFlag) AND
      closeRising AND (NOT openBtn)));

errorFlag := obstacle OR (prevErrorFlag AND (NOT bothRising));

prevOpenBtn := openBtn;
prevCloseBtn := closeBtn;
prevMotorUp := motorUp;
prevMotorDown := motorDown;
prevErrorFlag := errorFlag;

END_FUNCTION_BLOCK