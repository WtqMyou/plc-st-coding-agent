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
    history : ARRAY[0..99] OF LREAL;
    historyCount : INT;
    historyIndex : INT;
    activeCount : INT;
    total : LREAL;
    startIndex : INT;
    i : INT;
    triggerPrevious : BOOL;
END_VAR

error := FALSE;
status := 16#0000;

IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := 16#8200;
    average := 0.0;
    windowSizeReached := FALSE;
    historyCount := 0;
    historyIndex := 0;
ELSIF reset THEN
    historyCount := 0;
    historyIndex := 0;
    activeCount := 0;
    average := 0.0;
    windowSizeReached := FALSE;
    error := FALSE;
    status := 16#0000;
ELSIF cyclicExecution OR (trigger AND NOT triggerPrevious) THEN
    history[historyIndex] := value;
    historyIndex := historyIndex + 1;
    IF historyIndex >= 100 THEN
        historyIndex := 0;
    END_IF;

    IF historyCount < 100 THEN
        historyCount := historyCount + 1;
    END_IF;

    activeCount := historyCount;
    IF activeCount > windowSize THEN
        activeCount := windowSize;
    END_IF;

    IF activeCount > 0 THEN
        startIndex := (historyIndex - activeCount + 100) MOD 100;
        total := 0.0;

        FOR i := 0 TO activeCount - 1 DO
            total := total + history[startIndex];
            startIndex := startIndex + 1;
            IF startIndex >= 100 THEN
                startIndex := 0;
            END_IF;
        END_FOR;

        average := total / INT_TO_LREAL(activeCount);
    ELSE
        average := 0.0;
    END_IF;

    windowSizeReached := historyCount >= windowSize;
END_IF;

triggerPrevious := trigger;

END_FUNCTION_BLOCK