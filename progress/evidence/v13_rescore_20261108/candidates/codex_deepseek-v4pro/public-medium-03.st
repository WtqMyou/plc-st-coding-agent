FUNCTION_BLOCK FB
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
    samples : ARRAY[0..99] OF LREAL;
    sampleCount : INT := 0;
    sum : LREAL := 0.0;
    triggerOld : BOOL;
    triggerRising : BOOL;
    i : INT;
    j : INT;
END_VAR

triggerRising := trigger AND NOT triggerOld;

IF windowSize < 1 OR windowSize > 100 THEN
    IF reset THEN
        sampleCount := 0;
        sum := 0.0;
    END_IF

    error := TRUE;
    status := 16#8200;
    average := 0.0;
    windowSizeReached := FALSE;
ELSE
    error := FALSE;
    status := 16#0000;

    IF reset THEN
        sampleCount := 0;
        sum := 0.0;
        average := 0.0;
        windowSizeReached := FALSE;
    ELSE
        IF sampleCount > windowSize THEN
            j := 0;
            FOR i := sampleCount - windowSize TO sampleCount - 1 DO
                samples[j] := samples[i];
                j := j + 1;
            END_FOR
            sampleCount := windowSize;
        END_IF

        IF cyclicExecution OR triggerRising THEN
            IF sampleCount < windowSize THEN
                samples[sampleCount] := value;
                sampleCount := sampleCount + 1;
            ELSE
                IF windowSize > 1 THEN
                    FOR i := 0 TO windowSize - 2 DO
                        samples[i] := samples[i + 1];
                    END_FOR
                END_IF
                samples[windowSize - 1] := value;
            END_IF
        END_IF

        sum := 0.0;
        IF sampleCount > 0 THEN
            FOR i := 0 TO sampleCount - 1 DO
                sum := sum + samples[i];
            END_FOR
            average := sum / INT_TO_LREAL(sampleCount);
            windowSizeReached := sampleCount >= windowSize;
        ELSE
            average := 0.0;
            windowSizeReached := FALSE;
        END_IF
    END_IF
END_IF

triggerOld := trigger;

END_FUNCTION_BLOCK