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
    state        : INT;
    prevOpenBtn  : BOOL;
    prevCloseBtn : BOOL;
    prevObstacle : BOOL;
    prevMotorUp  : BOOL;
    prevMotorDown: BOOL;
    prevErrorFlag: BOOL;
END_VAR
VAR_CONSTANT
    IDLE    : INT := 0;
    OPENING : INT := 1;
    CLOSING : INT := 2;
    FAULT   : INT := 3;
END_VAR

    // Rising edge detection
    VAR
        openRising   : BOOL;
        closeRising  : BOOL;
        doubleRising : BOOL;
    END_VAR
    openRising   := openBtn AND NOT prevOpenBtn;
    closeRising  := closeBtn AND NOT prevCloseBtn;
    doubleRising := (openBtn AND closeBtn) AND NOT (prevOpenBtn AND prevCloseBtn);

    // State transitions
    CASE state OF
    IDLE:
        // Clear fault on double-button rising edge when no obstacle
        IF doubleRising AND NOT obstacle THEN
            errorFlag := FALSE;
        END_IF;

        // Start opening: new rising edge on openBtn, closeBtn not held, no open limit
        IF openRising AND NOT closeBtn AND NOT openLimit AND NOT errorFlag THEN
            state    := OPENING;
            motorUp  := TRUE;
            motorDown:= FALSE;
        // Start closing: new rising edge on closeBtn, openBtn not held, no close limit
        ELSIF closeRising AND NOT openBtn AND NOT closeLimit AND NOT errorFlag THEN
            state    := CLOSING;
            motorUp  := FALSE;
            motorDown:= TRUE;
        ELSE
            motorUp  := FALSE;
            motorDown:= FALSE;
        END_IF;

    OPENING:
        // Obstacle detected: enter FAULT immediately
        IF obstacle THEN
            state     := FAULT;
            errorFlag := TRUE;
            motorUp   := FALSE;
            motorDown := FALSE;
        // Open limit reached: stop and return to IDLE
        ELSIF openLimit THEN
            state     := IDLE;
            motorUp   := FALSE;
            motorDown := FALSE;
        ELSE
            motorUp   := TRUE;
            motorDown := FALSE;
        END_IF;

    CLOSING:
        // Obstacle detected: enter FAULT immediately
        IF obstacle THEN
            state     := FAULT;
            errorFlag := TRUE;
            motorUp   := FALSE;
            motorDown := FALSE;
        // Close limit reached: stop and return to IDLE
        ELSIF closeLimit THEN
            state     := IDLE;
            motorUp   := FALSE;
            motorDown := FALSE;
        ELSE
            motorUp   := FALSE;
            motorDown := TRUE;
        END_IF;

    FAULT:
        // Latched: stay in FAULT unless double-button rising edge appears with no obstacle
        IF prevErrorFlag AND NOT obstacle AND doubleRising THEN
            state     := IDLE;
            errorFlag := FALSE;
            motorUp   := FALSE;
            motorDown := FALSE;
        ELSE
            errorFlag := TRUE;
            motorUp   := FALSE;
            motorDown := FALSE;
        END_IF;
    END_CASE;

    // Latch error flag once set (overrides any later state logic)
    IF errorFlag THEN
        motorUp   := FALSE;
        motorDown := FALSE;
    END_IF;

    // Update previous-cycle state for next scan
    prevOpenBtn   := openBtn;
    prevCloseBtn  := closeBtn;
    prevObstacle  := obstacle;
    prevMotorUp   := motorUp;
    prevMotorDown := motorDown;
    prevErrorFlag := errorFlag;
END_FUNCTION_BLOCK