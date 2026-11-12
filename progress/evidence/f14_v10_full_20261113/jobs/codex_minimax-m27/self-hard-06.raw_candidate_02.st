The error is on line 65: assigning WORD to BOOL. Let me fix the `tmpTwoAgoPrevCond` variable and the consecutive 3-scan tracking logic.
FUNCTION_BLOCK FB
VAR_INPUT
    runRequest      : BOOL;
    pressure        : REAL;
    pressureValid   : BOOL;
    fuelFlow        : REAL;
    steamFlow       : REAL;
    outletCmd       : INT;
    outletFeedback  : INT;
    resetBtn        : BOOL;
END_VAR
VAR_OUTPUT
    tripLatched     : BOOL;
    fuelPermit      : BOOL;
    currentCauseMask: WORD;
    latchedCauseMask: WORD;
    diagnosticActive: BOOL;
END_VAR
VAR
    prevResetBtn            : BOOL := FALSE;
    prevRunRequest          : BOOL := FALSE;
    prevPressureValid       : BOOL := FALSE;
    prevPressure            : REAL := 0.0;
    prevOutletCmd           : INT := 0;
    prevOutletFeedback      : INT := 0;
    prevTripLatched         : BOOL := FALSE;
    prevCurrentCauseMask    : WORD := 0;
    prevLatchedCauseMask    : WORD := 0;
    prevStuckCond           : BOOL := FALSE;
    prev2StuckCond          : BOOL := FALSE;
    tmpRisingReset          : BOOL;
    tmpStuckCond            : BOOL;
    tmpCurrentMask          : WORD;
    tmpOverpressureValid    : BOOL;
END_VAR

(* CONTRACT:
   | Output/State    | Activation         | Retention       | Reset/Deactivation           | Same-scan Priority | Units/Boundaries       |
   |-----------------|--------------------|-----------------|-------------------------------|--------------------|------------------------|
   | tripLatched     | runRequest & (!pressureValid OR pressure>=4500.0) | Hold until resetBtn rising & !runRequest & pressureValid & pressure<=4200.0 | resetBtn rising edge clears | Same-scan with clue calc | BOOL; 4500/4200 kPa hysteresis |
   | fuelPermit      | runRequest & !tripLatched | None (combinational) | Clears when tripLatched sets | Same-scan | BOOL |
   | currentCauseMask| Recalc every scan | None (recalculated) | Zero when !runRequest | Same-scan | WORD bits 0-3; 0,1,2,4,6,8 only |
   | latchedCauseMask| OR into when tripLatched | Accumulate across trip | Clear on valid reset | Same-scan | WORD bits 0-3; 0-15 |
   | diagnosticActive| currentCauseMask <> 0 | None | Clears when mask zero | Same-scan | BOOL |
   | prevStuckCond   | Stores stuckCond from prev scan | Hold until next scan | Reset on condition break | Per-scan memory | BOOL |
   | prev2StuckCond  | Stores prevStuckCond from 2 scans ago | Hold | Reset on condition break | Per-scan memory | BOOL |
*)
(* CONTRACT_RULES [] *)

tmpRisingReset := resetBtn AND NOT prevResetBtn;

tmpOverpressureValid := runRequest AND pressureValid AND (pressure >= 4500.0);

tmpStuckCond := tmpOverpressureValid AND (outletCmd >= 50) AND (outletFeedback <= 10);

tmpCurrentMask := 0;

IF NOT runRequest THEN
    tmpCurrentMask := 0;
    prevStuckCond := FALSE;
    prev2StuckCond := FALSE;
ELSIF NOT pressureValid THEN
    tmpCurrentMask := 1;
    prevStuckCond := FALSE;
    prev2StuckCond := FALSE;
ELSE
    IF tmpOverpressureValid THEN
        IF tmpStuckCond AND prevStuckCond AND prev2StuckCond THEN
            tmpCurrentMask := tmpCurrentMask OR 2;
        END_IF;
        
        IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
            tmpCurrentMask := tmpCurrentMask OR 4;
        END_IF;
        
        IF tmpCurrentMask = 0 THEN
            tmpCurrentMask := 8;
        END_IF;
    ELSE
        tmpCurrentMask := 0;
    END_IF;
    
    prev2StuckCond := prevStuckCond;
    prevStuckCond := tmpStuckCond;
END_IF;

currentCauseMask := tmpCurrentMask;

IF tmpRisingReset AND NOT runRequest AND pressureValid AND (pressure <= 4200.0) THEN
    tripLatched := FALSE;
    latchedCauseMask := 0;
ELSIF runRequest AND (NOT pressureValid OR (pressure >= 4500.0)) THEN
    tripLatched := TRUE;
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
ELSIF tripLatched THEN
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
ELSE
    tripLatched := FALSE;
    latchedCauseMask := 0;
END_IF;

fuelPermit := runRequest AND NOT tripLatched;

diagnosticActive := (currentCauseMask <> 0);

prevResetBtn := resetBtn;
prevRunRequest := runRequest;
prevPressureValid := pressureValid;
prevPressure := pressure;
prevOutletCmd := outletCmd;
prevOutletFeedback := outletFeedback;
prevTripLatched := tripLatched;
prevCurrentCauseMask := currentCauseMask;
prevLatchedCauseMask := latchedCauseMask;

END_FUNCTION_BLOCK