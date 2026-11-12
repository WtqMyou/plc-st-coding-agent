FUNCTION_BLOCK FB
VAR
    buffer      : ARRAY[0..7] OF REAL;
    writeIndex  : INT := 0;
    sampleCount : INT := 0;
    windowFull  : BOOL := FALSE;
    sum         : REAL := 0.0;
END_VAR

VAR_INPUT
    enable   : BOOL;
    rawValue : REAL;
END_VAR

VAR_OUTPUT
    filteredValue : REAL := 0.0;
    windowFull    : BOOL := FALSE;
    sampleCount   : INT := 0;
END_VAR

BEGIN
    IF enable THEN
        // Determine index of oldest sample
        IF windowFull THEN
            // Buffer is full; oldest is at writeIndex
            sum := sum - buffer[writeIndex];
        ELSE
            // Buffer not full; oldest is at index 0
            IF sampleCount > 0 THEN
                sum := sum - buffer[0];
            END_IF;
        END_IF;

        // Add new sample
        sum := sum + rawValue;
        buffer[writeIndex] := rawValue;

        // Advance circular write pointer
        writeIndex := (writeIndex + 1) MOD 8;

        // Update sample count (cap at 8)
        IF sampleCount < 8 THEN
            sampleCount := sampleCount + 1;
        END_IF;

        // Update window full flag
        windowFull := (sampleCount = 8);

        // Compute arithmetic mean of valid samples
        IF sampleCount > 0 THEN
            filteredValue := sum / INT_TO_REAL(sampleCount);
        END_IF;
    ELSE
        // Enable is FALSE: clear all state
        sampleCount := 0;
        windowFull  := FALSE;
        writeIndex  := 0;
        sum         := 0.0;
        // filteredValue is NOT updated—holds last computed value
    END_IF;
END_FUNCTION_BLOCK