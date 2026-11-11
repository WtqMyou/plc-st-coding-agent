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
    prevOpenBtn : BOOL;
    prevCloseBtn : BOOL;
    edgeOpen : BOOL;
    edgeClose : BOOL;
    edgeBoth : BOOL;
END_VAR

edgeOpen := openBtn AND NOT prevOpenBtn;
edgeClose := closeBtn AND NOT prevCloseBtn;
edgeBoth := (openBtn AND closeBtn) AND NOT (prevOpenBtn AND prevCloseBtn);

IF obstacle THEN
    state := 3;
    motorUp := FALSE;
    motorDown := FALSE;
    errorFlag := TRUE;
ELSIF state = 3 THEN
    IF edgeBoth THEN
        state := 0;
        errorFlag := FALSE;
    ELSE
        state := 3;
        errorFlag := TRUE;
    END_IF;
    motorUp := FALSE;
    motorDown := FALSE;
ELSIF state = 1 THEN
    IF openLimit THEN
        state := 0;
        motorUp := FALSE;
    ELSE
        state := 1;
        motorUp := TRUE;
    END_IF;
    motorDown := FALSE;
    errorFlag := FALSE;
ELSIF state = 2 THEN
    IF closeLimit THEN
        state := 0;
        motorDown := FALSE;
    ELSE
        state := 2;
        motorDown := TRUE;
    END_IF;
    motorUp := FALSE;
    errorFlag := FALSE;
ELSE
    IF edgeOpen AND NOT closeBtn AND NOT openLimit THEN
        state := 1;
        motorUp := TRUE;
        motorDown := FALSE;
    ELSIF edgeClose AND NOT openBtn AND NOT closeLimit THEN
        state := 2;
        motorDown := TRUE;
        motorUp := FALSE;
    ELSE
        state := 0;
        motorUp := FALSE;
        motorDown := FALSE;
    END_IF;
    errorFlag := FALSE;
END_IF;

prevOpenBtn := openBtn;
prevCloseBtn := closeBtn;
END_FUNCTION_BLOCK