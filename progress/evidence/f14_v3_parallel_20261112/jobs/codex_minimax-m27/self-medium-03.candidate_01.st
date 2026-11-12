FUNCTION_BLOCK FB
VAR_INPUT
    openBtn    : BOOL;
    closeBtn   : BOOL;
    openLimit  : BOOL;
    closeLimit : BOOL;
    obstacle   : BOOL;
END_VAR
VAR_OUTPUT
    motorUp    : BOOL := FALSE;
    motorDown  : BOOL := FALSE;
    errorFlag  : BOOL := FALSE;
END_VAR
VAR
    state       : UINT := 0;  // 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT
    prevOpenBtn : BOOL := FALSE;
    prevCloseBtn: BOOL := FALSE;
END_VAR
VAR
    openBtnRising     : BOOL;
    closeBtnRising    : BOOL;
    bothBtnRising     : BOOL;
    prevBothBtn       : BOOL;
END_VAR

openBtnRising  := openBtn  AND NOT prevOpenBtn;
closeBtnRising := closeBtn AND NOT prevCloseBtn;
bothBtnRising  := (openBtn AND closeBtn) AND NOT prevBothBtn;

IF obstacle THEN
    state := FAULT;
    errorFlag := TRUE;
    motorUp   := FALSE;
    motorDown := FALSE;
ELSE
    CASE state OF
        0:  // IDLE
            motorUp   := FALSE;
            motorDown := FALSE;
            IF openBtnRising AND NOT closeBtn AND NOT openLimit THEN
                state := OPENING;
                motorUp := TRUE;
            ELSIF closeBtnRising AND NOT openBtn AND NOT closeLimit THEN
                state := CLOSING;
                motorDown := TRUE;
            END_IF;

        1:  // OPENING
            motorUp   := TRUE;
            motorDown := FALSE;
            IF openLimit THEN
                state := IDLE;
                motorUp := FALSE;
            END_IF;

        2:  // CLOSING
            motorUp   := FALSE;
            motorDown := TRUE;
            IF closeLimit THEN
                state := IDLE;
                motorDown := FALSE;
            END_IF;

        3:  // FAULT
            motorUp   := FALSE;
            motorDown := FALSE;
            IF bothBtnRising THEN
                state := IDLE;
            END_IF;
    END_CASE;
END_IF;

errorFlag      := (state = FAULT);
prevOpenBtn    := openBtn;
prevCloseBtn   := closeBtn;
prevBothBtn    := (openBtn AND closeBtn);

END_FUNCTION_BLOCK