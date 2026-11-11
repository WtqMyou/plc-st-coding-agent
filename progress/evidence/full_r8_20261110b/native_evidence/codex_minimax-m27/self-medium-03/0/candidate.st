FUNCTION_BLOCK FB
VAR_INPUT
    openBtn   : BOOL;
    closeBtn  : BOOL;
    openLimit : BOOL;
    closeLimit: BOOL;
    obstacle  : BOOL;
END_VAR
VAR_OUTPUT
    motorUp   : BOOL;
    motorDown : BOOL;
    errorFlag : BOOL;
END_VAR
VAR
    prevOpenBtn   : BOOL;
    prevCloseBtn  : BOOL;
    prevObstacle  : BOOL;
    prevMotorUp   : BOOL;
    prevMotorDown : BOOL;
    prevErrorFlag : BOOL;
END_VAR

    IF prevOpenBtn   = FALSE
       AND prevCloseBtn  = FALSE
       AND prevMotorUp   = FALSE
       AND prevMotorDown = FALSE
       AND prevErrorFlag = FALSE THEN
        motorUp   := FALSE;
        motorDown := FALSE;
        errorFlag := FALSE;
    END_IF

    IF obstacle THEN
        motorUp   := FALSE;
        motorDown := FALSE;
        errorFlag := TRUE;
    END_IF

    IF openLimit THEN
        motorUp := FALSE;
    END_IF

    IF closeLimit THEN
        motorDown := FALSE;
    END_IF

    IF NOT obstacle AND NOT openLimit AND NOT closeLimit THEN
        IF prevMotorUp OR (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag AND prevOpenBtn AND NOT prevCloseBtn) THEN
            motorUp := TRUE;
        ELSIF prevMotorDown OR (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag AND prevCloseBtn AND NOT prevOpenBtn) THEN
            motorDown := TRUE;
        END_IF
    END_IF

    IF prevOpenBtn AND prevCloseBtn AND openBtn AND closeBtn THEN
        IF prevErrorFlag THEN
            errorFlag := FALSE;
            motorUp   := FALSE;
            motorDown := FALSE;
        ELSE
            errorFlag := TRUE;
        END_IF
    END_IF

    prevOpenBtn   := openBtn;
    prevCloseBtn  := closeBtn;
    prevObstacle  := obstacle;
    prevMotorUp   := motorUp;
    prevMotorDown := motorDown;
    prevErrorFlag := errorFlag;
END_FUNCTION_BLOCK