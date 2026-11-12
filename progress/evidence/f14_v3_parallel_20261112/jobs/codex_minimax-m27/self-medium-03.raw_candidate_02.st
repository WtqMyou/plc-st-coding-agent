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
    state        : UINT := 0;
    prevOpenBtn  : BOOL := FALSE;
    prevCloseBtn : BOOL := FALSE;
    openBtnRising  : BOOL;
    closeBtnRising : BOOL;
    bothBtnRising  : BOOL;
END_VAR

openBtnRising  := openBtn  AND NOT prevOpenBtn;
closeBtnRising := closeBtn AND NOT prevCloseBtn;
bothBtnRising  := (openBtn AND closeBtn) AND (prevOpenBtn OR prevCloseBtn);

IF obstacle THEN
    state := 3;
    errorFlag := TRUE;
    motorUp   := FALSE;
    motorDown := FALSE;
ELSE
    CASE state OF
        0:  // IDLE
            motorUp   := FALSE;
            motorDown := FALSE;
            IF openBtnRising AND NOT closeBtn AND NOT openLimit THEN
                state := 1;
                motorUp := TRUE;
            ELSIF closeBtnRising AND NOT openBtn AND NOT closeLimit THEN
                state := 2;
                motorDown := TRUE;
            END_IF;

        1:  // OPENING
            motorUp   := TRUE;
            motorDown := FALSE;
            IF openLimit THEN
                state := 0;
                motorUp := FALSE;
            END_IF;

        2:  // CLOSING
            motorUp   := FALSE;
            motorDown := TRUE;
            IF closeLimit THEN
                state := 0;
                motorDown := FALSE;
            END_IF;

        3:  // FAULT
            motorUp   := FALSE;
            motorDown := FALSE;
            IF bothBtnRising THEN
                state := 0;
            END_IF;
    END_CASE;
END_IF;

errorFlag := (state = 3);
prevOpenBtn  := openBtn;
prevCloseBtn := closeBtn;

END_FUNCTION_BLOCK