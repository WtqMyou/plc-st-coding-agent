FUNCTION_BLOCK FB_MovingAverage
VAR_INPUT
    cyclicExecution  : BOOL;  // When TRUE, periodic reading is performed
    trigger          : BOOL;  // External trigger signal, reads value upon each rising edge
    value            : LREAL; // Newly read data value
    windowSize       : INT;   // Window size for moving average (1-100)
    reset            : BOOL;  // Reset signal, resets the moving average calculation when TRUE
END_VAR

VAR_OUTPUT
    average          : LREAL; // The moving average result
    windowSizeReached: BOOL;  // FALSE: Maximum window width not yet reached
                              // TRUE: Maximum window width has been reached
    error            : BOOL;  // FALSE: No error occurred, TRUE: An error occurred
    status           : WORD;  // Status code
END_VAR

VAR
    dataBuffer       : ARRAY[1..100] OF LREAL; // Circular buffer for data values
    sum              : LREAL;                   // Sum of values in current window
    validSampleCount : INT;                     // Number of valid samples in buffer
    prevTrigger      : BOOL;                    // Previous trigger state for edge detection
END_VAR

// ============================================================================
// Reset Handling
// ============================================================================
IF reset THEN
    sum              := 0.0;
    validSampleCount := 0;
    average          := 0.0;
    windowSizeReached := FALSE;
    error            := FALSE;
    status           := 16#0000;
    prevTrigger      := FALSE;
    RETURN;
END_IF

// ============================================================================
// Window Size Validation
// ============================================================================
IF windowSize < 1 OR windowSize > 100 THEN
    error  := TRUE;
    status := 16#8200;  // Window length setting error
    RETURN;
END_IF

// Clear error on successful validation
error  := FALSE;
status := 16#0000;     // Execution successful

// ============================================================================
// Process New Value
// Condition: cyclicExecution is TRUE OR trigger has a rising edge
// ============================================================================
IF cyclicExecution OR (trigger AND NOT prevTrigger) THEN
    // When buffer is full, remove the oldest value from sum
    IF validSampleCount >= windowSize THEN
        sum := sum - dataBuffer[1];
        
        // Shift buffer elements left (simple shifting approach)
        FOR i := 1 TO windowSize - 1 DO
            dataBuffer[i] := dataBuffer[i + 1];
        END_FOR
    END_IF
    
    // Add new value to buffer
    dataBuffer[validSampleCount + 1] := value;
    sum := sum + value;
    
    // Update sample count (max is windowSize)
    IF validSampleCount < windowSize THEN
        validSampleCount := validSampleCount + 1;
    END_IF
    
    // Calculate average
    average := sum / INT_TO_LREAL(validSampleCount);
    
    // Check if window has been filled to maximum size
    windowSizeReached := (validSampleCount = windowSize);
END_IF

// ============================================================================
// Update Trigger State for Rising Edge Detection
// ============================================================================
prevTrigger := trigger;

END_FUNCTION_BLOCK