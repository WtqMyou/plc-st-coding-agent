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
    state        : INT;
    prevOpenBtn  : BOOL;
    prevCloseBtn : BOOL;
    prevObstacle : BOOL;
    prevErrorFlag: BOOL;
END_VAR

    // Sample inputs
    VAR
        openRising  : BOOL;
        closeRising : BOOL;
        bothRising  : BOOL;
    END_VAR
    openRising  := openBtn AND NOT prevOpenBtn;
    closeRising := closeBtn AND NOT prevCloseBtn;
    bothRising  := (openBtn AND closeBtn) AND NOT (prevOpenBtn AND prevCloseBtn);

    // Initialize outputs to off
    motorUp   := FALSE;
    motorDown := FALSE;

    // Obstacle handling has highest priority in all states
    IF obstacle THEN
        state     := 3; // FAULT
        errorFlag := TRUE;
        motorUp   := FALSE;
        motorDown := FALSE;
    ELSE
        CASE state OF
        0: // IDLE
            // Reset fault with dual-button rising edge while obstacle clear
            IF prevErrorFlag AND bothRising THEN
                errorFlag := FALSE;
                state    := 0;
            ELSE
                errorFlag := FALSE;
            END_IF;
            // Start opening: rising edge on openBtn, closeBtn not pressed, not at open limit
            IF openRising AND NOT closeBtn AND NOT openLimit THEN
                state    := 1; // OPENING
                motorUp  := TRUE;
            // Start closing: rising edge on closeBtn, openBtn not pressed, not at close limit
            ELSIF closeRising AND NOT openBtn AND NOT closeLimit THEN
                state    := 2; // CLOSING
                motorDown:= TRUE;
            END_IF;

        1: // OPENING
            // Stop when open limit reached
            IF openLimit THEN
                state  := 0;
            ELSE
                motorUp := TRUE;
            END_IF;

        2: // CLOSING
            // Stop when close limit reached
            IF closeLimit THEN
                state    := 0;
            ELSE
                motorDown := TRUE;
            END_IF;

        3: // FAULT
            errorFlag := TRUE;
            // Clear fault only when no obstacle and dual-button rising edge appears
            IF prevErrorFlag AND bothRising THEN
                state    := 0;
                errorFlag := FALSE;
            END_IF;
        END_CASE;
    END_IF;

    // Update previous-cycle samples
    prevOpenBtn   := openBtn;
    prevCloseBtn  := closeBtn;
    prevObstacle  := obstacle;
    prevErrorFlag := errorFlag;
END_FUNCTION_BLOCK