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
    sampleCount : INT;
    writePosition : INT;
    bufferSum : LREAL;
    triggerPrevious : BOOL;
END_VAR

error := FALSE;
status := 16#0000;

IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := 16#8200;
    average := 0.0;
    windowSizeReached := FALSE;
    sampleCount := 0;
    writePosition := 0;
    bufferSum := 0.0;
ELSIF reset THEN
    sampleCount := 0;
    writePosition := 0;
    bufferSum := 0.0;
    average := 0.0;
    windowSizeReached := FALSE;
    error := FALSE;
    status := 16#0000;
ELSIF cyclicExecution OR (trigger AND NOT triggerPrevious) THEN
    IF sampleCount < windowSize THEN
        buffer[sampleCount] := value;
        sampleCount := sampleCount + 1;
    ELSE
        bufferSum := bufferSum - buffer[writePosition];
        buffer[writePosition] := value;
        writePosition := writePosition + 1;
        IF writePosition >= windowSize THEN
            writePosition := 0;
        END_IF;
    END_IF;

    bufferSum := bufferSum + value;
    windowSizeReached := sampleCount >= windowSize;

    IF sampleCount > 0 THEN
        average := bufferSum / INT_TO_LREAL(sampleCount);
    ELSE
        average := 0.0;
    END_IF;
END_IF;

triggerPrevious := trigger;

END_FUNCTION_BLOCK