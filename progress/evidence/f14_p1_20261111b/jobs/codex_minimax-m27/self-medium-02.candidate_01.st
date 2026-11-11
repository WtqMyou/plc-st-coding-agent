FUNCTION_BLOCK FB
VAR_INPUT
    enable      : BOOL;
    rawValue    : REAL;
END_VAR

VAR_OUTPUT
    filteredValue : REAL := 0.0;
    windowFull    : BOOL := FALSE;
    sampleCount   : INT  := 0;
END_VAR

VAR
    buffer     : ARRAY[0..7] OF REAL;
    writeIndex : INT := 0;
    sum        : REAL;
    i          : INT;
    prev_enable : BOOL := FALSE;
END_VAR

// Initialization on rising edge or first power-up with enable already TRUE
IF enable AND sampleCount = 0 THEN
    writeIndex  := 0;
    sampleCount := 0;
    windowFull  := FALSE;
END_IF;

// Detect rising edge on enable
IF enable AND NOT prev_enable THEN
    writeIndex  := 0;
    sampleCount := 0;
    windowFull  := FALSE;
END_IF;

IF enable THEN
    // Write new sample into circular buffer
    buffer[writeIndex] := rawValue;
    writeIndex := (writeIndex + 1) MOD 8;

    // Increment sample count (cap at 8)
    IF sampleCount < 8 THEN
        sampleCount := sampleCount + 1;
    END_IF;

    // Set windowFull flag when 8 samples accumulated
    IF sampleCount = 8 THEN
        windowFull := TRUE;
    END_IF;

    // Calculate sum of valid samples in circular buffer
    sum := 0.0;
    IF sampleCount = 8 THEN
        // Buffer full: sum all 8 samples (oldest at writeIndex)
        FOR i := 0 TO 7 DO
            sum := sum + buffer[i];
        END_FOR;
        filteredValue := sum / 8.0;
    ELSE
        // Buffer not full: sum first sampleCount samples
        FOR i := 0 TO sampleCount - 1 DO
            sum := sum + buffer[i];
        END_FOR;
        filteredValue := sum / INT_TO_REAL(sampleCount);
    END_IF;
ELSE
    // enable = FALSE: clear count and full flag, keep filteredValue unchanged
    sampleCount := 0;
    windowFull  := FALSE;
END_IF;

// Track previous enable state for edge detection
prev_enable := enable;
END_FUNCTION_BLOCK