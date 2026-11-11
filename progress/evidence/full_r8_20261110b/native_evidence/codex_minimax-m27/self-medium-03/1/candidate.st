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
    prevBothPressed: BOOL;
END_VAR

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
        IF prevMotorUp THEN
            motorUp := TRUE;
        ELSIF prevMotorDown THEN
            motorDown := TRUE;
        ELSIF NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag THEN
            IF openBtn AND NOT prevOpenBtn AND NOT closeBtn THEN
                motorUp := TRUE;
            ELSIF closeBtn AND NOT prevCloseBtn AND NOT openBtn THEN
                motorDown := TRUE;
            END_IF
        END_IF
    END_IF

    IF prevBothPressed THEN
        IF prevErrorFlag THEN
            errorFlag := FALSE;
        ELSE
            errorFlag := TRUE;
        END_IF;
    END_IF;

    prevOpenBtn    := openBtn;
    prevCloseBtn   := closeBtn;
    prevObstacle   := obstacle;
    prevMotorUp    := motorUp;
    prevMotorDown  := motorDown;
    prevErrorFlag  := errorFlag;
    prevBothPressed := openBtn AND closeBtn;
END_FUNCTION_BLOCK