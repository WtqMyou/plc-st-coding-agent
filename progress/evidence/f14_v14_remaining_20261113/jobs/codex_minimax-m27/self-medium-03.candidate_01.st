// ENGINEERING_CONTRACT
// Pub IDs | Activation           | Retention                 | Explicit Reset           | Same-scan Priority | Units
// --------|----------------------|---------------------------|--------------------------|--------------------|------
// motorUp | Rising openBtn in    | Run until openLimit or    | obstacle->stop, reset->  | obstacle > limits  | BOOL
//         | IDLE, no obstacle,   | obstacle, stays latched   | stop, other outputs off  | > new start        |
//         | closeBtn=FALSE,      | during fault              |                          |                    |
//         | !openLimit           |                           |                          |                    |
// --------|----------------------|---------------------------|--------------------------|--------------------|------
// motorDown| Rising closeBtn in  | Run until closeLimit or   | obstacle->stop, reset->  | obstacle > limits  | BOOL
//         | IDLE, no obstacle,   | obstacle, stays latched   | stop, other outputs off  | > new start        |
//         | openBtn=FALSE,       | during fault              |                          |                    |
//         | !closeLimit          |                           |                          |                    |
// --------|----------------------|---------------------------|--------------------------|--------------------|------
// errorFlag| obstacle in any     | Latch until valid reset   | reset: no obstacle AND   | always highest     | BOOL
//         | state                | (requires no obstacle     | rising bothBtns          | priority           |
//         |                      | AND rising bothBtns)      |                          |                    |
// --------|----------------------|---------------------------|--------------------------|--------------------|------
// CONTRACT_RULES [{"kind":"hold_until_reset","output":"errorFlag","set_input":"obstacle","reset_input":"risingBothBtn"}]

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
    state        : INT; // 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT
    prevOpenBtn  : BOOL;
    prevCloseBtn : BOOL;
    prevObstacle : BOOL;
    prevErrorFlag: BOOL;
    bothHeldPrev : BOOL;
END_VAR
VAR
    risingOpenBtn  : BOOL;
    risingCloseBtn : BOOL;
    risingBothBtn  : BOOL;
END_VAR

    // Rising edge detection
    risingOpenBtn  := openBtn AND NOT prevOpenBtn;
    risingCloseBtn := closeBtn AND NOT prevCloseBtn;
    risingBothBtn  := (openBtn AND closeBtn) AND NOT bothHeldPrev;

    // ---- Priority 1: Obstacle handling ----
    IF obstacle THEN
        motorUp   := FALSE;
        motorDown := FALSE;
        errorFlag := TRUE;
        state     := 3; // FAULT
        GOTO scan_end;
    END_IF;

    // ---- Priority 2: Fault state latching ----
    IF state = 3 THEN
        // Latched: motors off, wait for valid reset
        motorUp   := FALSE;
        motorDown := FALSE;
        // Valid reset: no obstacle AND rising both buttons
        IF risingBothBtn THEN
            errorFlag := FALSE;
            state     := 0; // IDLE
        ELSE
            errorFlag := TRUE;
        END_IF;
        GOTO scan_end;
    END_IF;

    // ---- Normal operation: IDLE, OPENING, CLOSING ----
    CASE state OF
        0: // IDLE
            motorUp   := FALSE;
            motorDown := FALSE;
            // Start opening: rising openBtn, closeBtn=FALSE, no obstacle, not at limit
            IF risingOpenBtn AND NOT closeBtn AND NOT openLimit THEN
                motorUp  := TRUE;
                motorDown:= FALSE;
                state    := 1; // OPENING
            // Start closing: rising closeBtn, openBtn=FALSE, no obstacle, not at limit
            ELSIF risingCloseBtn AND NOT openBtn AND NOT closeLimit THEN
                motorUp   := FALSE;
                motorDown := TRUE;
                state     := 2; // CLOSING
            END_IF;

        1: // OPENING
            motorUp   := TRUE;
            motorDown := FALSE;
            // Stop at open limit
            IF openLimit THEN
                motorUp  := FALSE;
                motorDown:= FALSE;
                state    := 0; // IDLE
            END_IF;

        2: // CLOSING
            motorUp   := FALSE;
            motorDown := TRUE;
            // Stop at close limit
            IF closeLimit THEN
                motorUp  := FALSE;
                motorDown:= FALSE;
                state    := 0; // IDLE
            END_IF;
    END_CASE;

scan_end:
    // Update previous inputs for next scan
    prevOpenBtn   := openBtn;
    prevCloseBtn  := closeBtn;
    prevObstacle  := obstacle;
    prevErrorFlag := errorFlag;
    bothHeldPrev  := openBtn AND closeBtn;

END_FUNCTION_BLOCK