FUNCTION_BLOCK FB
VAR_INPUT
    openBtn    : BOOL;
    closeBtn   : BOOL;
    openLimit  : BOOL;
    closeLimit : BOOL;
    obstacle   : BOOL;
END_VAR
VAR_OUTPUT
    motorUp   : BOOL;
    motorDown : BOOL;
    errorFlag : BOOL;
END_VAR
VAR
    state        : INT := 0; (* 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT *)
    openBtnPrev  : BOOL := FALSE;
    closeBtnPrev : BOOL := FALSE;
    bothPrev     : BOOL := FALSE;
    openBtnRise  : BOOL;
    closeBtnRise : BOOL;
    bothPressed  : BOOL;
    resetRise    : BOOL;
END_VAR

openBtnRise  := openBtn AND NOT openBtnPrev;
closeBtnRise := closeBtn AND NOT closeBtnPrev;
bothPressed  := openBtn AND closeBtn;
resetRise    := bothPressed AND NOT bothPrev;

CASE state OF
    0: (* IDLE *)
        motorUp   := FALSE;
        motorDown := FALSE;
        errorFlag := FALSE;

        IF openBtnRise AND NOT openLimit THEN
            state := 1;
        ELSIF closeBtnRise AND NOT closeLimit THEN
            state := 2;
        END_IF;

    1: (* OPENING *)
        IF obstacle THEN
            motorUp   := FALSE;
            motorDown := FALSE;
            errorFlag := TRUE;
            state     := 3;
        ELSIF openLimit THEN
            motorUp   := FALSE;
            motorDown := FALSE;
            errorFlag := FALSE;
            state     := 0;
        ELSE
            motorUp   := TRUE;
            motorDown := FALSE;
            errorFlag := FALSE;
        END_IF;

    2: (* CLOSING *)
        IF obstacle THEN
            motorDown := FALSE;
            errorFlag := FALSE;
            state     := 1;

            IF openLimit THEN
                motorUp := FALSE;
            ELSE
                motorUp := TRUE;
            END_IF;
        ELSIF closeLimit THEN
            motorUp   := FALSE;
            motorDown := FALSE;
            errorFlag := FALSE;
            state     := 0;
        ELSE
            motorUp   := FALSE;
            motorDown := TRUE;
            errorFlag := FALSE;
        END_IF;

    3: (* FAULT *)
        motorUp   := FALSE;
        motorDown := FALSE;
        errorFlag := TRUE;

        IF resetRise AND NOT obstacle THEN
            errorFlag := FALSE;
            state     := 0;
        END_IF;
END_CASE;

openBtnPrev  := openBtn;
closeBtnPrev := closeBtn;
bothPrev     := bothPressed;
END_FUNCTION_BLOCK