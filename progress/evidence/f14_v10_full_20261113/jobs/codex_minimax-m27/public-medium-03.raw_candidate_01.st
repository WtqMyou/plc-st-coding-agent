(*
ENGINEERING_CONTRACT
================================================================================
Output State Summary:
- average:     ACTIVATION on cyclicExecution=TRUE OR rising trigger edge | RETAIN between updates
- windowSizeReached: RETAIN | FALSE until sampleCount>=windowSize | reset clears to FALSE
- error:       RETAIN | set TRUE on windowSize outside [1,100] | reset clears to FALSE
- status:      RETAIN | 16#0000=success, 16#8200=windowSize error | reset clears to 16#0000

Scan Priority (same-scan):
- cyclicExecution=TRUE → add value and exit; trigger ignored (PUB001/PUB002 priority)
- cyclicExecution=FALSE AND trigger rising edge → add value (PUB002)

Reset Behavior (PUB005):
- reset=TRUE → clear all state, set status=16#0000, error=FALSE; no output update same scan
- reset is level-triggered; next scan after reset=FALSE resumes normal operation

Boundary Constraints:
- windowSize: [1,100] inclusive (PUB003)
- average = sum / windowSize when sampleCount>=windowSize, else sum/sampleCount
- Division guard: MAX(1,sampleCount) prevents zero-divide on first value
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
END_VAR

METHOD PRIVATE AddValueAndUpdateAverage : BOOL
VAR
    oldestValue : LREAL;
END_VAR

    oldestValue := 0.0;

    IF sampleCount >= windowSize THEN
        oldestValue := dataBuffer[currentIndex];
    END_IF;

    dataBuffer[currentIndex] := value;
    sum := sum + value - oldestValue;

    currentIndex := currentIndex + 1;
    IF currentIndex > windowSize THEN
        currentIndex := 1;
    END_IF;

    IF sampleCount < windowSize THEN
        sampleCount := sampleCount + 1;
    END_IF;

    windowSizeReached := (sampleCount >= windowSize);

    average := sum / TO_LREAL(MAX(1, sampleCount));

    AddValueAndUpdateAverage := TRUE;
END_METHOD

IF reset THEN
    currentIndex := 0;
    sampleCount := 0;
    sum := 0.0;
    windowSizeReached := FALSE;
    error := FALSE;
    status := 16#0000;
    average := 0.0;
    prevTrigger := trigger;
    RETURN;
END_IF;

IF windowSize < 1 OR windowSize > 100 THEN
    error := TRUE;
    status := 16#8200;
    prevTrigger := trigger;
    RETURN;
END_IF;

error := FALSE;
status := 16#0000;

IF cyclicExecution THEN
    AddValueAndUpdateAverage();
ELSIF trigger AND NOT prevTrigger THEN
    AddValueAndUpdateAverage();
END_IF;

prevTrigger := trigger;
END_FUNCTION_BLOCK