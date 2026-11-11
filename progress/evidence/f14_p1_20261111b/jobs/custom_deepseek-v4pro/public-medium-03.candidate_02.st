FUNCTION_BLOCK FB_MovingAverage
VAR_INPUT
    cyclicExecution : BOOL;
    trigger : BOOL;
    value : LREAL;
    windowSize : INT;
    reset : BOOL;
END_VAR
VAR_OUTPUT
    average : LREAL;
    windowSizeReached : BOOL;
    error : BOOL;
    status : WORD;
END_VAR
VAR
    buffer : ARRAY[1..100] OF LREAL;
    count : INT := 0;
    sum : LREAL := 0.0;
    lastTrigger : BOOL := FALSE;
    triggerEdge : BOOL;
    i : INT;
END_VAR

// Rising edge detection for external trigger
triggerEdge := trigger AND NOT lastTrigger;
lastTrigger := trigger;

// Validate window size
IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := 16#8200;
    average := 0.0;
    windowSizeReached := FALSE;
    count := 0;
    sum := 0.0;
    FOR i := 1 TO 100 DO
        buffer[i] := 0.0;
    END_FOR;
ELSE
    error := FALSE;
    status := 16#0000;

    IF reset THEN
        // Reset all internal state
        count := 0;
        sum := 0.0;
        FOR i := 1 TO 100 DO
            buffer[i] := 0.0;
        END_FOR;
    ELSIF cyclicExecution OR triggerEdge THEN
        // New value should be added
        IF count < windowSize THEN
            // Still filling the window
            count := count + 1;
            buffer[count] := value;
            sum := sum + value;
        ELSE
            // Window full: remove oldest, add newest
            sum := sum - buffer[1] + value;
            // Shift buffer left
            IF windowSize > 1 THEN
                FOR i := 1 TO windowSize - 1 DO
                    buffer[i] := buffer[i + 1];
                END_FOR;
            END_IF;
            buffer[windowSize] := value;
        END_IF;
    END_IF;

    IF count > 0 THEN
        average := sum / INT_TO_LREAL(count);
    ELSE
        average := 0.0;
    END_IF;
    windowSizeReached := (count >= windowSize);
END_IF;

END_FUNCTION_BLOCK