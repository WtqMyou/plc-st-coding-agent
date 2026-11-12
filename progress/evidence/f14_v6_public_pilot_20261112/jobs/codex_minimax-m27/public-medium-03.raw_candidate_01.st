{engineer}
(* CONTRACT_RULES [] *)
(* ENGINEERING_CONTRACT
 * ID              | Activation                    | Retention         | Reset/Deactivation | Priority   | Units/Boundaries
 * ----------------------------------------------------------------------------------------------------------------------------------
 * average         | cyclicExecution=TRUE          | Until next value  | reset=TRUE         | Same-scan  | LREAL, output
 *                 | trigger rising edge           |                   |                    |            |
 * windowSizeReached | currentWindowSize=windowSize | Until reset       | reset=TRUE         | Same-scan  | BOOL, output
 * error           | windowSize < 1 OR > 100       | Until reset       | reset=TRUE         | Same-scan  | BOOL, output
 * status          | Derived from windowSize check | Until reset       | reset=TRUE         | Same-scan  | WORD: 16#0000 or 16#8200
 * 
 * Data buffer: circular buffer of 100 LREAL entries (max window size)
 * Sum maintained incrementally for O(1) average calculation
 * PUB001, PUB002, PUB003, PUB004, PUB006, PUB007
 *)
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
    dataBuffer : ARRAY[1..100] OF LREAL;
    bufferIndex : INT := 0;
    currentWindowSize : INT := 0;
    sum : LREAL := 0.0;
    lastTrigger : BOOL := FALSE;
END_VAR

// Reset handling
IF reset THEN
    bufferIndex := 0;
    currentWindowSize := 0;
    sum := 0.0;
    average := 0.0;
    windowSizeReached := FALSE;
    error := FALSE;
    status := 16#0000;
    lastTrigger := FALSE;
    RETURN;
END_IF;

// Validate window size
IF windowSize < 1 OR windowSize > 100 THEN
    error := TRUE;
    status := 16#8200;
    RETURN;
END_IF;

// Cyclic execution takes priority over trigger
IF cyclicExecution THEN
    IF currentWindowSize >= windowSize THEN
        // Window is full, replace oldest value
        bufferIndex := (bufferIndex MOD windowSize) + 1;
        sum := sum - dataBuffer[bufferIndex] + value;
        average := sum / TO_LREAL(windowSize);
    ELSE
        // Window not yet full, add new value
        bufferIndex := bufferIndex + 1;
        dataBuffer[bufferIndex] := value;
        sum := sum + value;
        currentWindowSize := bufferIndex;
        average := sum / TO_LREAL(currentWindowSize);
    END_IF;
    
    windowSizeReached := (currentWindowSize >= windowSize);
    error := FALSE;
    status := 16#0000;
    RETURN;
END_IF;

// Trigger-based execution on rising edge
IF trigger AND NOT lastTrigger THEN
    IF currentWindowSize >= windowSize THEN
        // Window is full, replace oldest value
        bufferIndex := (bufferIndex MOD windowSize) + 1;
        sum := sum - dataBuffer[bufferIndex] + value;
        average := sum / TO_LREAL(windowSize);
    ELSE
        // Window not yet full, add new value
        bufferIndex := bufferIndex + 1;
        dataBuffer[bufferIndex] := value;
        sum := sum + value;
        currentWindowSize := bufferIndex;
        average := sum / TO_LREAL(currentWindowSize);
    END_IF;
    
    windowSizeReached := (currentWindowSize >= windowSize);
    error := FALSE;
    status := 16#0000;
END_IF;

lastTrigger := trigger;
END_FUNCTION_BLOCK