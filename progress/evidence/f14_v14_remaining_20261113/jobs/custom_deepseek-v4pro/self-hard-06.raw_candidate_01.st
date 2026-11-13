(* ENGINEERING_CONTRACT
  tripLatched: active same scan on trip condition (run & !pressureValid) OR (run & pressureValid & pressure>=4500.0);
               retains until legal reset edge: resetBtn rising & !run & pressureValid & pressure<=4200.0.
  fuelPermit: combinational = run & !tripLatched, evaluated after latch update.
  currentCauseMask: low nibble recalculated each scan; !run=0, invalid=1, valid overpressure evaluates stuck/excess/unlocated, below 4500=0.
  latchedCauseMask: OR currentCauseMask while tripLatched; clear when !tripLatched; low 4 bits only.
  stuckCounter: counts consecutive full overpressure+valve-condition scans; reset on any interruption.
  diagnosticActive: currentCauseMask<>0.
  Unspecified: scan period undefined; initial resetBtn edge state considered FALSE.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    pressure : REAL;
    pressureValid : BOOL;
    fuelFlow : REAL;
    steamFlow : REAL;
    outletCmd : INT;
    outletFeedback : INT;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    tripLatched : BOOL;
    fuelPermit : BOOL;
    currentCauseMask : WORD;
    latchedCauseMask : WORD;
    diagnosticActive : BOOL;
END_VAR
VAR
    lastResetBtn : BOOL := FALSE;
    stuckCounter : INT := 0;
    tmp_resetRising : BOOL;
    tmp_overpressure : BOOL;
    tmp_invalid : BOOL;
    tmp_tripCondition : BOOL;
    tmp_legalReset : BOOL;
    tmp_stuckCond : BOOL;
    tmp_stuckBit : BOOL;
    tmp_excessBit : BOOL;
END_VAR

tmp_resetRising := resetBtn AND NOT lastResetBtn;
lastResetBtn := resetBtn;

tmp_overpressure := runRequest AND pressureValid AND pressure >= 4500.0;
tmp_invalid := runRequest AND NOT pressureValid;
tmp_tripCondition := tmp_overpressure OR tmp_invalid;
tmp_legalReset := tmp_resetRising AND NOT runRequest AND pressureValid AND pressure <= 4200.0;

IF NOT runRequest THEN
    currentCauseMask := WORD#0;
    stuckCounter := 0;
ELSIF NOT pressureValid THEN
    currentCauseMask := WORD#1;
    stuckCounter := 0;
ELSIF pressure >= 4500.0 THEN
    tmp_stuckCond := (outletCmd >= 50) AND (outletFeedback <= 10);
    IF tmp_stuckCond THEN
        stuckCounter := stuckCounter + 1;
    ELSE
        stuckCounter := 0;
    END_IF;
    tmp_stuckBit := stuckCounter >= 3;
    tmp_excessBit := (fuelFlow >= 4.0) AND (steamFlow <= 10.0);
    IF tmp_stuckBit AND tmp_excessBit THEN
        currentCauseMask := WORD#6;
    ELSIF tmp_excessBit THEN
        currentCauseMask := WORD#4;
    ELSIF tmp_stuckBit THEN
        currentCauseMask := WORD#2;
    ELSE
        currentCauseMask := WORD#8;
    END_IF;
ELSE
    currentCauseMask := WORD#0;
    stuckCounter := 0;
END_IF;

IF tmp_tripCondition THEN
    tripLatched := TRUE;
ELSIF tmp_legalReset THEN
    tripLatched := FALSE;
END_IF;

IF tripLatched THEN
    latchedCauseMask := (latchedCauseMask OR currentCauseMask) AND WORD#15;
ELSE
    latchedCauseMask := WORD#0;
END_IF;

fuelPermit := runRequest AND NOT tripLatched;
diagnosticActive := currentCauseMask <> WORD#0;

END_FUNCTION_BLOCK