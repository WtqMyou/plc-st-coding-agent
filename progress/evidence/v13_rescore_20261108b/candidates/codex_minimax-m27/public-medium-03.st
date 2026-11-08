FUNCTION_BLOCK FB
VAR_INPUT
    cyclicExecution : BOOL;
    trigger : BOOL;
    value : LREAL;
    windowSize : INT;
    reset : BOOL;
END_VAR

VAR_OUTPUT
    average : LREAL := 0.0;
    windowSizeReached : BOOL := FALSE;
    error : BOOL := FALSE;
    status : WORD := 16#0000;
END_VAR

VAR
    dataBuffer : ARRAY[1..100] OF LREAL;
    sampleCount : INT := 0;
    nextIndex : INT := 1;
    lastTrigger : BOOL := FALSE;
    sum : LREAL;
    i : INT;
END_VAR

// Reset on rising edge when no error
IF reset AND NOT error THEN
    sampleCount := 0;
    nextIndex := 1;
    average := 0.0;
    windowSizeReached := FALSE;
END_IF

// Window size validation
IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := 16#8200;
    IF error THEN
        RETURN;
    END_IF
END_IF

// Clear error when window size becomes valid
IF NOT error THEN
    error := FALSE;
    status := 16#0000;
END_IF

// Handle cyclic or trigger-based updates
IF cyclicExecution OR (trigger AND NOT lastTrigger) THEN
    IF sampleCount < windowSize THEN
        sampleCount := sampleCount + 1;
        dataBuffer[sampleCount] := value;
    ELSE
        dataBuffer[nextIndex] := value;
        nextIndex := (nextIndex MOD windowSize) + 1;
    END_IF
    
    // Recalculate average
    sum := 0.0;
    FOR i := 1 TO sampleCount DO
        sum := sum + dataBuffer[i];
    END_FOR
    average := sum / INT_TO_LREAL(sampleCount);
END_IF

// Update window size reached flag
windowSizeReached := (sampleCount >= windowSize);

// Update lastTrigger
lastTrigger := trigger;

END_FUNCTION_BLOCK