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
    dataBuffer : ARRAY[1..100] OF LREAL;
    sum : LREAL;
    count : INT;
    writeIndex : INT;
    lastTrigger : BOOL;
    lastReset : BOOL;
    initValid : BOOL;
END_VAR

// Reset handling
IF reset AND NOT lastReset THEN
    sum := 0.0;
    count := 0;
    writeIndex := 0;
    average := 0.0;
    windowSizeReached := FALSE;
    error := FALSE;
    status := 16#0000;
    initValid := FALSE;
END_IF;
lastReset := reset;

// Validate window size on first execution or when reset was just released
IF NOT initValid THEN
    IF windowSize < 1 OR windowSize > 100 THEN
        error := TRUE;
        status := 16#8200;
        RETURN;
    ELSE
        error := FALSE;
        status := 16#0000;
        initValid := TRUE;
    END_IF;
END_IF;

// Check for cyclic execution mode
IF cyclicExecution THEN
    // Validate window size on each cycle
    IF windowSize < 1 OR windowSize > 100 THEN
        error := TRUE;
        status := 16#8200;
        RETURN;
    ELSE
        error := FALSE;
        status := 16#0000;
    END_IF;
    
    // Process new value
    IF count >= windowSize THEN
        sum := sum - dataBuffer[writeIndex + 1];
    ELSE
        count := count + 1;
    END_IF;
    
    writeIndex := (writeIndex MOD windowSize) + 1;
    dataBuffer[writeIndex] := value;
    sum := sum + value;
    
    IF count >= windowSize THEN
        windowSizeReached := TRUE;
    ELSE
        windowSizeReached := FALSE;
    END_IF;
    
    average := sum / INT_TO_LREAL(count);
    lastTrigger := FALSE;
    RETURN;
END_IF;

// Check for rising edge on trigger
IF trigger AND NOT lastTrigger THEN
    // Validate window size
    IF windowSize < 1 OR windowSize > 100 THEN
        error := TRUE;
        status := 16#8200;
        lastTrigger := trigger;
        RETURN;
    ELSE
        error := FALSE;
        status := 16#0000;
    END_IF;
    
    // Process new value
    IF count >= windowSize THEN
        sum := sum - dataBuffer[writeIndex + 1];
    ELSE
        count := count + 1;
    END_IF;
    
    writeIndex := (writeIndex MOD windowSize) + 1;
    dataBuffer[writeIndex] := value;
    sum := sum + value;
    
    IF count >= windowSize THEN
        windowSizeReached := TRUE;
    ELSE
        windowSizeReached := FALSE;
    END_IF;
    
    average := sum / INT_TO_LREAL(count);
END_IF;

lastTrigger := trigger;
END_FUNCTION_BLOCK