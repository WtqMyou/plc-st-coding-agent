FUNCTION_BLOCK FB_MovingAverage
(* Engineering Contract
 * ┌─────────────────────────────────────────────────────────────────────────────────────┐
 * │ OUTPUT STATE TABLE                                                                │
 * ├─────────────┬────────────────────────────────────────────────────────────────────┤
 * │ average     │ HOLD: Retained between scans; updated when valid sample processed.  │
 * │             │ RETAIN on reset: Returns to 0.0 via sum reset.                      │
 * │ windowSizeReached│ ACTIVE: TRUE when sampleCount >= windowSize (PUB001 window).   │
 * │             │ DEACTIVATION: Set FALSE on reset.                                   │
 * │ error       │ ACTIVE: TRUE when windowSize invalid (<1 or >100).                  │
 * │             │ DEACTIVATION: Set FALSE when reset clears error.                    │
 * │ status      │ RETAIN: 16#8200 when invalid windowSize; 16#0000 otherwise.         │
 * │             │ RESET: Set to 16#0000 on valid reset or valid windowSize.           │
 * ├─────────────┼────────────────────────────────────────────────────────────────────┤
 * │ TRIGGER     │ Rising edge on trigger input (PUB003). Edge detection via           │
 * │             │ triggerPrev state variable. Same-scan priority: cyclicExecution     │
 * │             │ checked first per PUB002.                                           │
 * ├─────────────┼────────────────────────────────────────────────────────────────────┤
 * │ WINDOW      │ Bounded 1..100 (PUB004). Circular buffer (100 elements).            │
 * │ BOUNDARIES  │ Sample count saturates at windowSize.                               │
 * │             │ Zero-value behavior: valid input, included in average per PUB001.   │
 * ├─────────────┼────────────────────────────────────────────────────────────────────┤
 * │ CITATIONS   │ PUB001: Moving arithmetic mean definition.                          │
 * │             │ PUB002: cyclicExecution periodic update.                            │
 * │             │ PUB003: External trigger rising edge.                               │
 * │             │ PUB004: Reset signal and window validation.                         │
 * │             │ PUB006: 16#0000 success status.                                     │
 * │             │ PUB007: 16#8200 window length error status.                         │
 * └─────────────┴────────────────────────────────────────────────────────────────────┘
 *)
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
    sampleCount : INT := 0;
    sumAccumulator : LREAL := 0.0;
    bufferIndex : INT := 0;
    triggerRisingEdge : BOOL := FALSE;
    prevTrigger : BOOL := FALSE;
END_VAR

IF reset THEN
    sampleCount := 0;
    sumAccumulator := 0.0;
    bufferIndex := 0;
    windowSizeReached := FALSE;
    error := FALSE;
    status := 16#0000;
    triggerRisingEdge := FALSE;
    prevTrigger := FALSE;
END_IF;

IF NOT error AND (cyclicExecution OR triggerRisingEdge) THEN
    bufferIndex := (bufferIndex MOD INT_TO_INT(windowSize)) + 1;
    
    IF sampleCount >= windowSize THEN
        sumAccumulator := sumAccumulator - dataBuffer[bufferIndex];
    ELSE
        sampleCount := sampleCount + 1;
    END_IF;
    
    dataBuffer[bufferIndex] := value;
    sumAccumulator := sumAccumulator + value;
    average := sumAccumulator / LREAL_TO_LREAL(INT_TO_LREAL(sampleCount));
    windowSizeReached := (sampleCount >= windowSize);
END_IF;

IF windowSize < 1 OR windowSize > 100 THEN
    error := TRUE;
    status := 16#8200;
END_IF;

prevTrigger := trigger;
triggerRisingEdge := trigger AND NOT prevTrigger;

END_FUNCTION_BLOCK