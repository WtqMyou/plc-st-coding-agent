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
    state         : INT := 0; (* 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT *)
    prevOpenBtn   : BOOL := FALSE;
    prevCloseBtn  : BOOL := FALSE;
    prevObstacle  : BOOL := FALSE;
    prevMotorUp   : BOOL := FALSE;
    prevMotorDown : BOOL := FALSE;
    prevErrorFlag : BOOL := FALSE;
END_VAR

VAR
    openRising  : BOOL;
    closeRising : BOOL;
    comboRising : BOOL;
END_VAR

openRising  := openBtn AND NOT prevOpenBtn;
closeRising := closeBtn AND NOT prevCloseBtn;
comboRising := (openBtn AND closeBtn) AND NOT (prevOpenBtn AND prevCloseBtn);

IF obstacle THEN
    state := 3;
    motorUp := FALSE;
    motorDown := FALSE;
    errorFlag := TRUE;
ELSIF state = 3 THEN
    motorUp := FALSE;
    motorDown := FALSE;
    IF comboRising THEN
        state := 0;
        errorFlag := FALSE;
    ELSE
        errorFlag := TRUE;
    END_IF;
ELSIF state = 1 THEN
    errorFlag := FALSE;
    motorDown := FALSE;
    IF openLimit THEN
        motorUp := FALSE;
        state := 0;
    ELSE
        motorUp := TRUE;
    END_IF;
ELSIF state = 2 THEN
    errorFlag := FALSE;
    motorUp := FALSE;
    IF closeLimit THEN
        motorDown := FALSE;
        state := 0;
    ELSE
        motorDown := TRUE;
    END_IF;
ELSE (* state = 0: IDLE *)
    motorUp := FALSE;
    motorDown := FALSE;
    errorFlag := FALSE;

    IF openRising AND NOT closeBtn AND NOT openLimit THEN
        motorUp := TRUE;
        state := 1;
    ELSIF closeRising AND NOT openBtn AND NOT closeLimit THEN
        motorDown := TRUE;
        state := 2;
    END_IF;
END_IF;

prevOpenBtn   := openBtn;
prevCloseBtn  := closeBtn;
prevObstacle  := obstacle;
prevMotorUp   := motorUp;
prevMotorDown := motorDown;
prevErrorFlag := errorFlag;
END_FUNCTION_BLOCK