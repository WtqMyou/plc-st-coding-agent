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
    prevOpenBtn   : BOOL;
    prevCloseBtn  : BOOL;
    prevObstacle  : BOOL;
    prevError     : BOOL;
    prevMotorUp   : BOOL;
    prevMotorDown : BOOL;
    state         : INT;
END_VAR
VAR_TEMP
    risingOpenBtn  : BOOL;
    risingCloseBtn : BOOL;
    risingBoth     : BOOL;
END_VAR

risingOpenBtn  := openBtn AND NOT prevOpenBtn;
risingCloseBtn := closeBtn AND NOT prevCloseBtn;
risingBoth     := openBtn AND closeBtn AND NOT (prevOpenBtn AND prevCloseBtn);

IF obstacle THEN
    motorUp   := FALSE;
    motorDown := FALSE;
    errorFlag := TRUE;
END_IF

IF errorFlag THEN
    motorUp   := FALSE;
    motorDown := FALSE;
    IF risingBoth AND NOT obstacle THEN
        errorFlag := FALSE;
        state := 0;
    END_IF;
ELSE
    motorUp := NOT obstacle AND NOT openLimit AND (prevMotorUp OR (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevError AND risingOpenBtn AND NOT closeBtn));
    motorDown := NOT obstacle AND NOT closeLimit AND (prevMotorDown OR (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevError AND risingCloseBtn AND NOT openBtn));
    IF risingOpenBtn AND NOT closeBtn THEN
        state := 1;
    ELSIF risingCloseBtn AND NOT openBtn THEN
        state := 2;
    ELSE
        state := 0;
    END_IF;
END_IF;

prevOpenBtn   := openBtn;
prevCloseBtn  := closeBtn;
prevObstacle  := obstacle;
prevError     := errorFlag;
prevMotorUp   := motorUp;
prevMotorDown := motorDown;
END_FUNCTION_BLOCK