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
    prevResetBtn    : BOOL;
    valveStickingCnt: INT;
END_VAR
VAR_TEMP
    resetRising     : BOOL;
    tmpMask         : WORD;
    overpressure    : BOOL;
    valveCondition  : BOOL;
    combustionCond  : BOOL;
    unlocatedCond   : BOOL;
END_VAR
// ENGINEERING_CONTRACT
// PUB003: tripLatched activates on runRequest AND (NOT pressureValid OR pressure>=4500.0)
// PUB004: tripLatched holds until valid reset rising edge
// PUB005: reset requires resetBtn rising edge AND NOT runRequest AND pressureValid AND pressure<=4200.0
// PUB006: currentCauseMask low 4 bits: bit0=1 transmitter fail, bit1=2 valve sticking, bit2=4 combustion excess, bit3=8 unlocated
// PUB007: valve sticking requires 3 consecutive scans; any break (condition fail / pressure drop / invalid / stop) clears counter
// PUB010: 300kPa hysteresis (trip at 4500.0, reset at 4200.0)
// PUB012: latchedCauseMask accumulates via bitwise OR during tripLatched; only valid reset clears to 0
// PUB014: fuelPermit = runRequest AND NOT tripLatched
// PUB015: diagnosticActive = currentCauseMask <> 0
// PUB016: NOT runRequest forces currentCauseMask=0 (bits are mutually exclusive per N10-S15)
// PUB017-018: allowed mask values {0,1,2,4,6,8}; N10-S11 validates bit1 requires 3 consecutive scans
// PUB019-022: same-scan behavior - trip and currentCauseMask computed from current inputs each scan
// PUB023-026: latchedCauseMask is historical accumulator, not snapshot; preserves full trip footprint
(* CONTRACT_RULES [] *)
;

resetRising := resetBtn AND NOT prevResetBtn;

tmpMask := 0;
overpressure := runRequest AND pressureValid AND (pressure >= 4500.0);
unlocatedCond := FALSE;

IF NOT runRequest THEN
    currentCauseMask := 0;
    valveStickingCnt := 0;
    tmpMask := 0;
ELSIF NOT pressureValid THEN
    currentCauseMask := 1;  // bit0
    valveStickingCnt := 0;
    tmpMask := 0;
ELSE
    valveCondition := (outletCmd >= 50) AND (outletFeedback <= 10);
    IF overpressure AND valveCondition THEN
        valveStickingCnt := valveStickingCnt + 1;
    ELSE
        valveStickingCnt := 0;
    END_IF;
    
    combustionCond := (fuelFlow >= 4.0) AND (steamFlow <= 10.0);
    
    IF valveStickingCnt >= 3 THEN
        tmpMask := TO_WORD(TO_UINT(tmpMask) OR 2);  // bit1
    END_IF;
    
    IF combustionCond THEN
        tmpMask := TO_WORD(TO_UINT(tmpMask) OR 4);  // bit2
    END_IF;
    
    IF overpressure AND ((tmpMask AND 2) = 0) AND ((tmpMask AND 4) = 0) THEN
        tmpMask := TO_WORD(TO_UINT(tmpMask) OR 8);  // bit3 unlocated
    END_IF;
    
    currentCauseMask := tmpMask;
END_IF;

IF tripLatched THEN
    IF resetRising AND NOT runRequest AND pressureValid AND (pressure <= 4200.0) THEN
        tripLatched := FALSE;
        latchedCauseMask := 0;
    ELSE
        latchedCauseMask := TO_WORD(TO_UINT(latchedCauseMask) OR TO_UINT(currentCauseMask));
    END_IF;
ELSE
    IF runRequest AND (NOT pressureValid OR (pressure >= 4500.0)) THEN
        tripLatched := TRUE;
        latchedCauseMask := currentCauseMask;
    ELSE
        tripLatched := FALSE;
        latchedCauseMask := 0;
    END_IF;
END_IF;

fuelPermit := runRequest AND NOT tripLatched;

diagnosticActive := (currentCauseMask <> 0);

prevResetBtn := resetBtn;

END_FUNCTION_BLOCK