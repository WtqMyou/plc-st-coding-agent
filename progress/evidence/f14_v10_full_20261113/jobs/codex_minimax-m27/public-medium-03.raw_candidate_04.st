(* ENGINEERING_CONTRACT
================================================================================
Output State Summary:
- average:     ACTIVATION on cyclicExecution=TRUE OR rising trigger edge | RETAIN
- windowSizeReached: RETAIN | FALSE until sampleCount>=windowSize | reset clears
- error:       RETAIN | set TRUE on windowSize outside [1,100] | reset clears
- status:      RETAIN | 16#0000=success, 16#8200=windowSize error | reset clears

Scan Priority (same-scan):
- cyclicExecution=TRUE → add value (trigger ignored) [PUB001/PUB002 priority]
- cyclicExecution=FALSE AND trigger rising edge → add value [PUB002]

Reset Behavior (PUB005):
- reset=TRUE → clear all state, set status=16#0000, exit immediately

Boundary Constraints (PUB003):
- windowSize: [1,100] inclusive
- average = sum / MIN(windowSize, sampleCount) when full, else sum/sampleCount
- Division guard: MAX(1,sampleCount) prevents zero-divide [PUB001]
- Window shrink: reset sampleCount and sum to force clean restart [replay fix]
================================================================================
*)

(* CONTRACT_RULES [] *)

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
    currentIndex : INT := 0;
    sampleCount : INT := 0;
    sum : LREAL := 0.0;
    prevTrigger : BOOL := FALSE;
    evictIndex : INT := 1;
    prevWindowSize : INT := 0;
END_VAR

VAR
    tmpAddValue : BOOL;
    tmpOldestValue : LREAL;
    tmp_WindowSizeChanged : BOOL;
END_VAR

tmpAddValue := FALSE;
tmp_WindowSizeChanged := FALSE;

IF reset THEN
    currentIndex := 0;
    sampleCount := 0;
    sum := 0.0;
    windowSizeReached := FALSE;
    error := FALSE;
    status := 16#0000;
    average := 0.0;
    prevTrigger := trigger;
    prevWindowSize := windowSize;
    RETURN;
END_IF;

IF windowSize < 1 OR windowSize > 100 THEN
    error := TRUE;
    status := 16#8200;
    prevTrigger := trigger;
    prevWindowSize := windowSize;
    RETURN;
END_IF;

error := FALSE;
status := 16#0000;

IF windowSize < prevWindowSize AND sampleCount > windowSize THEN
    tmp_WindowSizeChanged := TRUE;
    sampleCount := 0;
    sum := 0.0;
    currentIndex := 0;
    evictIndex := 1;
END_IF;

IF cyclicExecution THEN
    tmpAddValue := TRUE;
ELSIF trigger AND NOT prevTrigger THEN
    tmpAddValue := TRUE;
END_IF;

IF tmpAddValue THEN
    tmpOldestValue := 0.0;

    IF sampleCount >= windowSize THEN
        tmpOldestValue := dataBuffer[evictIndex];
        evictIndex := evictIndex + 1;
        IF evictIndex > windowSize THEN
            evictIndex := 1;
        END_IF;
    END_IF;

    currentIndex := currentIndex + 1;
    IF currentIndex > windowSize THEN
        currentIndex := 1;
    END_IF;

    dataBuffer[currentIndex] := value;
    sum := sum + value - tmpOldestValue;

    IF sampleCount < windowSize THEN
        sampleCount := sampleCount + 1;
    END_IF;

    windowSizeReached := (sampleCount >= windowSize);

    average := sum / TO_LREAL(MAX(1, sampleCount));
END_IF;

prevTrigger := trigger;
prevWindowSize := windowSize;
END_FUNCTION_BLOCK