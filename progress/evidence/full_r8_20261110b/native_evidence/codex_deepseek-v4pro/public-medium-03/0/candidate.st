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
    history      : ARRAY [0..99] OF LREAL;
    head         : INT := 0;
    storedCount  : INT := 0;
    lastTrigger  : BOOL;
    sampleNow    : BOOL;
    sampleCount  : INT;
    loopIndex    : INT;
    ringIndex    : INT;
    sum          : LREAL;
    validWindow  : BOOL;
END_VAR

sampleNow := cyclicExecution OR (trigger AND NOT lastTrigger);
lastTrigger := trigger;
validWindow := windowSize >= 1 AND windowSize <= 100;

IF reset THEN
    average := 0.0;
    windowSizeReached := FALSE;
    storedCount := 0;
    head := 0;

    IF validWindow THEN
        error := FALSE;
        status := 16#0000;
    ELSE
        error := TRUE;
        status := 16#8200;
    END_IF

ELSIF NOT validWindow THEN
    error := TRUE;
    status := 16#8200;

ELSE
    error := FALSE;
    status := 16#0000;

    IF sampleNow THEN
        IF head >= 99 THEN
            head := 0;
        ELSE
            head := head + 1;
        END_IF

        history[head] := value;

        IF storedCount < 100 THEN
            storedCount := storedCount + 1;
        END_IF
    END_IF

    windowSizeReached := storedCount >= windowSize;

    IF storedCount < windowSize THEN
        sampleCount := storedCount;
    ELSE
        sampleCount := windowSize;
    END_IF

    IF storedCount > 0 THEN
        sum := 0.0;

        FOR loopIndex := 0 TO sampleCount - 1 DO
            ringIndex := head - loopIndex;

            IF ringIndex < 0 THEN
                ringIndex := ringIndex + 100;
            END_IF

            sum := sum + history[ringIndex];
        END_FOR

        average := sum / INT_TO_LREAL(sampleCount);
    ELSE
        average := 0.0;
    END_IF
END_IF
END_FUNCTION_BLOCK