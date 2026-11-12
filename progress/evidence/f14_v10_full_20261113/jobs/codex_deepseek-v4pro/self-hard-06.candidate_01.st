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
    local_prevResetBtn : BOOL;
    local_prevTrip : BOOL;
    local_stickCounter : INT;
    local_latchedMask : WORD;
    tmp_resetRising : BOOL;
    tmp_legalReset : BOOL;
    tmp_invalid : BOOL;
    tmp_overpressure : BOOL;
    tmp_tripCondition : BOOL;
    tmp_stickQualified : BOOL;
    tmp_fuelExcess : BOOL;
    tmp_currentMask : WORD;
END_VAR

(* ENGINEERING_CONTRACT
   tripLatched: activate same scan on runRequest AND (NOT pressureValid OR pressure>=4500.0); hold until rising(resetBtn) AND NOT runRequest AND pressureValid AND pressure<=4200.0 [PUB006/PUB007].
   fuelPermit = runRequest AND NOT tripLatched; diagnosticActive iff currentCauseMask<>0 [PUB020].
   currentCauseMask recomputed every scan: 0 when stopped, 1 for invalid data; stick/fuel bits only evaluated during valid overpressure; bit3=8 when no located clue [PUB009-PUB014].
   stick bit1=2 requires three consecutive satisfied scans; any interruption resets count [PUB011/PUB015].
   latchedCauseMask is cumulative bitwise OR of currentCauseMask while tripped, cleared only on legal reset or untripped state [PUB016-PUB018].
   Units: pressure kPa, flows t/h, valve %. Unspecified: scan duration and reset-edge behavior while true trip condition exists.
*)

(* CONTRACT_RULES [] *)

tmp_resetRising := resetBtn AND NOT local_prevResetBtn;
tmp_legalReset := tmp_resetRising AND (NOT runRequest) AND pressureValid AND (pressure <= 4200.0);
tmp_invalid := runRequest AND (NOT pressureValid);
tmp_overpressure := runRequest AND pressureValid AND (pressure >= 4500.0);
tmp_tripCondition := tmp_invalid OR tmp_overpressure;

tripLatched := tmp_tripCondition OR (local_prevTrip AND (NOT tmp_legalReset));

tmp_currentMask := WORD#0;
IF NOT runRequest THEN
    tmp_currentMask := WORD#0;
    local_stickCounter := 0;
ELSIF NOT pressureValid THEN
    tmp_currentMask := WORD#1;
    local_stickCounter := 0;
ELSIF pressure < 4500.0 THEN
    tmp_currentMask := WORD#0;
    local_stickCounter := 0;
ELSE
    tmp_stickQualified := (outletCmd >= 50) AND (outletFeedback <= 10);
    IF tmp_stickQualified THEN
        local_stickCounter := local_stickCounter + 1;
        IF local_stickCounter > 3 THEN
            local_stickCounter := 3;
        END_IF;
    ELSE
        local_stickCounter := 0;
    END_IF;

    IF local_stickCounter >= 3 THEN
        tmp_currentMask := tmp_currentMask OR WORD#2;
    END_IF;

    tmp_fuelExcess := (fuelFlow >= 4.0) AND (steamFlow <= 10.0);
    IF tmp_fuelExcess THEN
        tmp_currentMask := tmp_currentMask OR WORD#4;
    END_IF;

    IF tmp_currentMask = WORD#0 THEN
        tmp_currentMask := WORD#8;
    END_IF;
END_IF;

currentCauseMask := tmp_currentMask;

IF tripLatched THEN
    local_latchedMask := local_latchedMask OR tmp_currentMask;
ELSE
    local_latchedMask := WORD#0;
END_IF;
latchedCauseMask := local_latchedMask;

fuelPermit := runRequest AND NOT tripLatched;
diagnosticActive := (tmp_currentMask <> WORD#0);

local_prevResetBtn := resetBtn;
local_prevTrip := tripLatched;

END_FUNCTION_BLOCK