FUNCTION_BLOCK FB
VAR_INPUT
    cyclicExecution : BOOL;
    trigger         : BOOL;
    value           : LREAL;
    windowSize      : INT;
    reset           : BOOL;
END_VAR
VAR_OUTPUT
    average           : LREAL;
    windowSizeReached : BOOL;
    error             : BOOL;
    status            : WORD;
END_VAR
VAR
    samples       : ARRAY[1..100] OF LREAL;
    sampleCount   : INT := 0;
    writeIndex    : INT := 0;
    sum           : LREAL := 0.0;
    prevTrigger   : BOOL := FALSE;
    firstScan     : BOOL := TRUE;
    i             : INT;
END_VAR

    // Validate window size
    IF windowSize < 1 OR windowSize > 100 THEN
        error  := TRUE;
        status := 16#8200;
        average           := 0.0;
        windowSizeReached := FALSE;
        RETURN;
    END_IF

    error  := FALSE;
    status := 16#0000;

    // Reset
    IF reset THEN
        average           := 0.0;
        windowSizeReached := FALSE;
        sampleCount       := 0;
        writeIndex        := 0;
        sum               := 0.0;
        firstScan         := FALSE;
        prevTrigger       := FALSE;
        RETURN;
    END_IF

    // Rising edge detection for trigger
    IF cyclicExecution THEN
        // cyclic mode: trigger has no effect
        IF firstScan THEN
            prevTrigger := FALSE;
            firstScan   := FALSE;
        END_IF
        IF writeIndex < windowSize THEN
            writeIndex          := writeIndex + 1;
            samples[writeIndex] := value;
            sum                 := sum + value;
            sampleCount         := writeIndex;
            IF sampleCount >= windowSize THEN
                windowSizeReached := TRUE;
                average           := sum / TO_LREAL(windowSize);
            ELSE
                average := sum / TO_LREAL(sampleCount);
            END_IF
        ELSE
            // Window full: slide
            sum := sum - samples[1];
            FOR i := 1 TO 99 DO
                samples[i] := samples[i + 1];
            END_FOR
            samples[windowSize] := value;
            sum                 := sum + value;
            windowSizeReached   := TRUE;
            average             := sum / TO_LREAL(windowSize);
        END_IF
    ELSE
        // Trigger mode
        IF firstScan THEN
            prevTrigger := trigger;
            firstScan   := FALSE;
        END_IF

        IF trigger AND NOT prevTrigger THEN
            // Rising edge on trigger: read one new sample
            IF writeIndex < windowSize THEN
                writeIndex          := writeIndex + 1;
                samples[writeIndex] := value;
                sum                 := sum + value;
                sampleCount         := writeIndex;
                IF sampleCount >= windowSize THEN
                    windowSizeReached := TRUE;
                    average           := sum / TO_LREAL(windowSize);
                ELSE
                    average := sum / TO_LREAL(sampleCount);
                END_IF
            ELSE
                // Window full: slide
                sum := sum - samples[1];
                FOR i := 1 TO 99 DO
                    samples[i] := samples[i + 1];
                END_FOR
                samples[windowSize] := value;
                sum                 := sum + value;
                windowSizeReached   := TRUE;
                average             := sum / TO_LREAL(windowSize);
            END_IF
        END_IF

        prevTrigger := trigger;
    END_IF

    // Handle windowSize shrinking below current sample count
    IF windowSize < sampleCount THEN
        sum := 0.0;
        FOR i := 1 TO windowSize DO
            samples[i] := samples[i + (sampleCount - windowSize)];
            sum        := sum + samples[i];
        END_FOR
        sampleCount := windowSize;
        writeIndex  := windowSize;
        IF windowSizeReached THEN
            average := sum / TO_LREAL(windowSize);
        END_IF
    END_IF
END_FUNCTION_BLOCK