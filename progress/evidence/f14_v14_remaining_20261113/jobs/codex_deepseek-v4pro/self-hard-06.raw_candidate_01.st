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
    tmp_resetPrev : BOOL;
    tmp_resetRising : BOOL;
    tmp_legalReset : BOOL;
    tmp_overpressure : BOOL;
    tmp_valvePred : BOOL;
    tmp_valveStuck : BOOL;
    tmp_combustion : BOOL;
    tmp_tripCondition : BOOL;
    tmp_tripNew : BOOL;
    tmp_previousLatched : WORD;
    tmp_stuckCycles : UINT;
END_VAR

(* ENGINEERING_CONTRACT
  tripLatched: set same scan by run & (!pressureValid OR pressure >= 4500.0); retained; cleared only legal reset edge (!run & valid & p <= 4200.0). PUB004-PUB007/PUB012.
  fuelPermit: run & NOT tripLatched. diagnosticActive: currentCauseMask <> 0. PUB021-PUB023.
  currentCauseMask low nibble: !run = 0; invalid = 1; valid overpressure = 2/4/6/8; valid below 4500 = 0. PUB024-PUB035.
  valve bit: 3 consecutive true scans of valid-overpressure valve criterion; any false criterion scan clears the cycle counter. PUB034.
  latchedCauseMask: when final tripLatched is true, old footprint OR current mask; zero when not tripped or on legal reset. PUB036.
  REAL boundaries inclusive: trip >= 4500.0, reset <= 4200.0, fuel >= 4.0, steam <= 10.0; cycles not seconds. PUB027/PUB040.
*)

(* CONTRACT_RULES [] *)

tmp_resetRising := resetBtn AND NOT tmp_resetPrev;
tmp_legalReset := tmp_resetRising AND NOT runRequest AND pressureValid AND (pressure <= 4200.0);

tmp_overpressure := runRequest AND pressureValid AND (pressure >= 4500.0);
tmp_valvePred := runRequest AND pressureValid AND (pressure >= 4500.0)
                 AND (outletCmd >= 50) AND (outletFeedback <= 10);
tmp_combustion := (fuelFlow >= 4.0) AND (steamFlow <= 10.0);

IF tmp_valvePred THEN
    IF tmp_stuckCycles < UINT#3 THEN
        tmp_stuckCycles := tmp_stuckCycles + UINT#1;
    END_IF;
ELSE
    tmp_stuckCycles := UINT#0;
END_IF;

tmp_valveStuck := tmp_stuckCycles >= UINT#3;

IF NOT runRequest THEN
    currentCauseMask := WORD#0;
ELSIF NOT pressureValid THEN
    currentCauseMask := WORD#1;
ELSIF pressure >= 4500.0 THEN
    IF tmp_valveStuck AND tmp_combustion THEN
        currentCauseMask := WORD#6;
    ELSIF tmp_valveStuck THEN
        currentCauseMask := WORD#2;
    ELSIF tmp_combustion THEN
        currentCauseMask := WORD#4;
    ELSE
        currentCauseMask := WORD#8;
    END_IF;
ELSE
    currentCauseMask := WORD#0;
END_IF;

tmp_tripCondition := runRequest AND (NOT pressureValid OR (pressure >= 4500.0));
tmp_previousLatched := latchedCauseMask;

tmp_tripNew := tripLatched;
IF tmp_legalReset THEN
    tmp_tripNew := FALSE;
ELSIF tmp_tripCondition THEN
    tmp_tripNew := TRUE;
END_IF;

IF tmp_legalReset THEN
    latchedCauseMask := WORD#0;
ELSIF tmp_tripNew THEN
    latchedCauseMask := tmp_previousLatched OR currentCauseMask;
ELSE
    latchedCauseMask := WORD#0;
END_IF;

tripLatched := tmp_tripNew;
fuelPermit := runRequest AND NOT tripLatched;
diagnosticActive := currentCauseMask <> WORD#0;

tmp_resetPrev := resetBtn;
END_FUNCTION_BLOCK