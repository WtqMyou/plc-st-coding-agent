FUNCTION_BLOCK FB_MovingAverage
VAR_INPUT
    cyclicExecution : BOOL;
    trigger : BOOL;
    value : LREAL;
    windowSize : INT;
    reset : BOOL;
END_VAR

VAR_OUTPUT
    average : LREAL := 0.0;
    windowSizeReached : BOOL := FALSE;
    error : BOOL := FALSE;
    status : WORD := 16#0000;
END_VAR

VAR
    buffer : ARRAY[1..100] OF LREAL;
    index : INT := 1;
    count : INT := 0;
    sum : LREAL := 0.0;
    prevCyclic : BOOL := FALSE;
    prevTrigger : BOOL := FALSE;
    prevReset : BOOL := FALSE;
END_VAR

// Reset on rising edge
IF reset AND NOT prevReset THEN
    index := 1;
    count := 0;
    sum := 0.0;
    average := 0.0;
    windowSizeReached := FALSE;
    error := FALSE;
    status := 16#0000;
END_IF;

// Validate window size
IF windowSize < 1 OR windowSize > 100 THEN
    error := TRUE;
    status := 16#8200;
    RETURN;
END_IF;

error := FALSE;
status := 16#0000;

// Process cyclic execution on rising edge
IF cyclicExecution AND NOT prevCyclic THEN
    // Add value
    sum := sum + value;
    buffer[index] := value;
    IF count < windowSize THEN
        count := count + 1;
        windowSizeReached := FALSE;
    ELSE
        sum := sum - buffer[index];
    END_IF;
    average := sum / INT_TO_LREAL(count);
    index := (index MOD windowSize) + 1;
END_IF;

// Process trigger on rising edge (only when cyclicExecution is FALSE)
IF (NOT cyclicExecution) AND trigger AND NOT prevTrigger THEN
    // Add value
    sum := sum + value;
    buffer[index] := value;
    IF count < windowSize THEN
        count := count + 1;
        windowSizeReached := FALSE;
    ELSE
        sum := sum - buffer[index];
    END_IF;
    average := sum / INT_TO_LREAL(count);
    index := (index MOD windowSize) + 1;
END_IF;

// Update previous states
prevCyclic := cyclicExecution;
prevTrigger := trigger;
prevReset := reset;
END_FUNCTION_BLOCK