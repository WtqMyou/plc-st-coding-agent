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
    buffer : ARRAY[0..99] OF LREAL;
    count : INT := 0;
    writeIndex : INT := 0;
    sum : LREAL := 0.0;
    prevTrigger : BOOL := FALSE;
    prevWindowSize : INT := 0;
    updateNow : BOOL;
END_VAR

IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := 16#8200;
    average := 0.0;
    windowSizeReached := FALSE;
    count := 0;
    writeIndex := 0;
    sum := 0.0;
ELSE
    error := FALSE;
    status := 16#0000;
    
    IF reset OR (windowSize <> prevWindowSize) THEN
        count := 0;
        writeIndex := 0;
        sum := 0.0;
        average := 0.0;
        windowSizeReached := FALSE;
    END_IF;
    prevWindowSize := windowSize;
    
    IF cyclicExecution THEN
        updateNow := TRUE;
    ELSIF (trigger AND NOT prevTrigger) THEN
        updateNow := TRUE;
    ELSE
        updateNow := FALSE;
    END_IF;
    
    IF updateNow THEN
        IF count < windowSize THEN
            buffer[writeIndex] := value;
            sum := sum + value;
            count := count + 1;
            writeIndex := writeIndex + 1;
        ELSE
            sum := sum - buffer[writeIndex] + value;
            buffer[writeIndex] := value;
            writeIndex := (writeIndex + 1) MOD windowSize;
        END_IF;
        IF count > 0 THEN
            average := sum / count;
        ELSE
            average := 0.0;
        END_IF;
        windowSizeReached := (count >= windowSize);
    END_IF;
END_IF;

prevTrigger := trigger;