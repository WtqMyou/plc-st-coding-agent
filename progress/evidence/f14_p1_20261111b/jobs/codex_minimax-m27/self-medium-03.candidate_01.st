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
    prev_openBtn  : BOOL := FALSE;
    prev_closeBtn : BOOL := FALSE;
    prev_obstacle : BOOL := FALSE;
    // Internal state: 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT
    state : INT := 0;
END_VAR
VAR
    risingEdgeOpen  : BOOL;
    risingEdgeClose : BOOL;
    risingEdgeBoth  : BOOL;
END_VAR

// ============================================================================
// Edge Detection
// ============================================================================
risingEdgeOpen  := openBtn  AND NOT prev_openBtn;
risingEdgeClose := closeBtn AND NOT prev_closeBtn;
risingEdgeBoth  := (openBtn AND closeBtn) AND NOT (prev_openBtn AND prev_closeBtn);

// ============================================================================
// Fault Handling (highest priority)
// ============================================================================
IF obstacle THEN
    errorFlag := TRUE;
    state := 3; // FAULT
END_IF;

// ============================================================================
// State Transitions & Motor Control
// ============================================================================
CASE state OF
    // ---- IDLE ----
    0: // IDLE
        IF errorFlag THEN
            // Already in fault, stay here
            motorUp   := FALSE;
            motorDown := FALSE;
        ELSE
            // Check for new open command
            IF risingEdgeOpen AND NOT closeBtn AND NOT openLimit AND NOT obstacle THEN
                state     := 1; // OPENING
                motorUp   := TRUE;
                motorDown := FALSE;
            // Check for new close command
            ELSIF risingEdgeClose AND NOT openBtn AND NOT closeLimit AND NOT obstacle THEN
                state     := 2; // CLOSING
                motorUp   := FALSE;
                motorDown := TRUE;
            ELSE
                motorUp   := FALSE;
                motorDown := FALSE;
            END_IF;
        END_IF;

    // ---- OPENING ----
    1: // OPENING
        IF obstacle THEN
            // Handled above, stay in fault
            motorUp   := FALSE;
            motorDown := FALSE;
        ELSIF openLimit THEN
            state     := 0; // IDLE
            motorUp   := FALSE;
            motorDown := FALSE;
        ELSE
            // Continue opening
            motorUp   := TRUE;
            motorDown := FALSE;
        END_IF;

    // ---- CLOSING ----
    2: // CLOSING
        IF obstacle THEN
            // Handled above, stay in fault
            motorUp   := FALSE;
            motorDown := FALSE;
        ELSIF closeLimit THEN
            state     := 0; // IDLE
            motorUp   := FALSE;
            motorDown := FALSE;
        ELSE
            // Continue closing
            motorUp   := FALSE;
            motorDown := TRUE;
        END_IF;

    // ---- FAULT ----
    3: // FAULT
        motorUp   := FALSE;
        motorDown := FALSE;
        // Reset only when no obstacle AND both buttons have new rising edge together
        IF NOT obstacle AND risingEdgeBoth THEN
            errorFlag := FALSE;
            state     := 0; // IDLE
        END_IF;
END_CASE;

// ============================================================================
// Update Previous States for Next Scan
// ============================================================================
prev_openBtn  := openBtn;
prev_closeBtn := closeBtn;
prev_obstacle := obstacle;

END_FUNCTION_BLOCK