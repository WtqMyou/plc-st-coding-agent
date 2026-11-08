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
    state        : INT := 0;   // 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT
    prevOpenBtn  : BOOL := FALSE;
    prevCloseBtn : BOOL := FALSE;
END_VAR

VAR
    openRising  : BOOL;
    closeRising : BOOL;
END_VAR

// Detect rising edges of the push‑button inputs
openRising  := openBtn AND NOT prevOpenBtn;
closeRising := closeBtn AND NOT prevCloseBtn;

// Update button history for next scan
prevOpenBtn  := openBtn;
prevCloseBtn := closeBtn;

// ------------------------------------------------------------
// Finite State Machine
// ------------------------------------------------------------
CASE state OF
    // --------------------------------------------------------
    // IDLE – waiting for a command
    // --------------------------------------------------------
    0:
        motorUp   := FALSE;
        motorDown := FALSE;
        errorFlag := FALSE;

        IF openRising AND NOT openLimit THEN
            state := 1;               // start opening
        ELSIF closeRising AND NOT closeLimit THEN
            state := 2;               // start closing
        END_IF

    // --------------------------------------------------------
    // OPENING – motor raises the gate
    // --------------------------------------------------------
    1:
        motorUp   := TRUE;
        motorDown := FALSE;
        errorFlag := FALSE;

        IF openLimit THEN
            state := 0;               // reached open limit
        ELSIF obstacle THEN
            motorUp   := FALSE;       // stop motor immediately
            errorFlag := TRUE;
            state := 3;               // enter fault state
        END_IF

    // --------------------------------------------------------
    // CLOSING – motor lowers the gate
    // --------------------------------------------------------
    2:
        motorUp   := FALSE;
        motorDown := TRUE;
        errorFlag := FALSE;

        IF closeLimit THEN
            state := 0;               // reached close limit
        ELSIF obstacle THEN
            motorDown := FALSE;       // stop downward motion
            IF openLimit THEN
                // Already at open limit → just stop
                state := 0;
            ELSE
                motorUp := TRUE;      // reverse to opening
                state := 1;
            END_IF
        END_IF

    // --------------------------------------------------------
    // FAULT – motor stopped, error latched
    // --------------------------------------------------------
    3:
        motorUp   := FALSE;
        motorDown := FALSE;
        errorFlag := TRUE;

        // Reset allowed only when obstacle cleared and both buttons pressed (rising edges)
        IF (NOT obstacle) AND openRising AND closeRising THEN
            errorFlag := FALSE;
            state := 0;
        END_IF

END_CASE
END_FUNCTION_BLOCK