(* ENGINEERING_CONTRACT
+----------------------------------------------------------------+
| Output/State | Activation          | Retention    | Reset       |
+----------------------------------------------------------------+
| average      | New value sampled   | HOLD         | reset=TRUE  |
| windowSizeReached | Window full   | HOLD         | reset=TRUE  |
| error        | windowSize invalid  | LATCHED      | reset=TRUE  |
| status       | Per-error condition | LATCHED      | reset=TRUE  |
+----------------------------------------------------------------+
| Same-scan priority: cyclicExecution > trigger rising edge      |
| Units: windowSize [1..100] slots; average [LREAL]              |
| Boundaries: sampleCount min=0 max=windowSize; index wraps 1-N  |
| Reset priority: reset=TRUE overrides all other inputs          |
| Error condition: windowSize < 1 OR windowSize > 100            |
| Status codes: 16#0000=OK, 16#8200=window size error            |
| Implementation: circular buffer with oldest-value replacement  |
+----------------------------------------------------------------+
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB_MovingAverage
VAR_INPUT
    cyclicExecution : BOOL;
    trigger : BOOL;
    value   : LREAL;
    windowSize : INT;
    reset   : BOOL;
END_VAR
VAR_OUTPUT
    average : LREAL;
    windowSizeReached : BOOL;
    error   : BOOL;
    status  : WORD;
END_VAR
VAR
    buffer : ARRAY[1..100] OF LREAL;
    writeIndex : INT := 0;
    sampleCount : INT := 0;
    sum : LREAL := 0.0;
    prevTrigger : BOOL := FALSE;
    prevWindowSize : INT := 0;
    tmpValid : BOOL;
    tmpRising : BOOL;
    tmpOldSlot : INT;
END_VAR

tmpValid := (windowSize >= 1) AND (windowSize <= 100);

IF tmpValid THEN
    error := FALSE;
    status := 16#0000;
    
    IF windowSize <> prevWindowSize THEN
        writeIndex := 0;
        sampleCount := 0;
        sum := 0.0;
        windowSizeReached := FALSE;
        prevWindowSize := windowSize;
    END_IF;
    
    IF reset THEN
        writeIndex := 0;
        sampleCount := 0;
        sum := 0.0;
        average := 0.0;
        windowSizeReached := FALSE;
    ELSIF cyclicExecution OR (trigger AND NOT prevTrigger) THEN
        tmpRising := trigger AND NOT prevTrigger;
        
        IF sampleCount >= windowSize THEN
            tmpOldSlot := ((writeIndex - windowSize) MOD windowSize) + 1;
            sum := sum - buffer[tmpOldSlot];
            sampleCount := sampleCount - 1;
        END_IF;
        
        writeIndex := (writeIndex MOD windowSize) + 1;
        buffer[writeIndex] := value;
        sum := sum + value;
        sampleCount := sampleCount + 1;
        
        IF sampleCount > 0 THEN
            average := sum / TO_LREAL(sampleCount);
        END_IF;
        
        windowSizeReached := (sampleCount >= windowSize);
    END_IF;
    
    prevTrigger := trigger;
ELSE
    error := TRUE;
    status := 16#8200;
END_IF;

END_FUNCTION_BLOCK