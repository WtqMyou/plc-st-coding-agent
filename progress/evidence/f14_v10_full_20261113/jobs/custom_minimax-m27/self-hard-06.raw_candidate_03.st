(* CONTRACT_RULES [{"kind": "hold_until_reset", "output": "tripLatched", "set_input": "runRequest_AND_NOT_pressureValid_OR_pressure_ge_4500", "reset_input": "resetBtn_rising_AND_NOT_runRequest_AND_pressureValid_AND_pressure_le_4200"}] *)
(* ENGINEERING_CONTRACT
   PUB001-PUB004:  Trip activation same-scan when runRequest AND (NOT pressureValid OR pressure >= 4500.0 kPa).
   PUB005:         Hysteresis band 300 kPa: reset clears only when pressure <= 4200.0 (strict <=).
   PUB006-PUB008:  tripLatched holds until resetBtn rising edge + NOT runRequest + pressureValid + pressure <= 4200.0.
   PUB009-PUB011:  currentCauseMask LOW-4 encoding: bit0=xmitter fail, bit1=valve stick(3-consecutive), bit2=excess combustion, bit3=unlocated.
                    Only evaluated when runRequest AND pressureValid AND pressure >= 4500.0 (bits 1/2); bit0 when runRequest AND NOT pressureValid.
                    Not runRequest → mask = 0.
   PUB012-PUB014:  Valve stick counter requires 3 consecutive cycles of (runRequest AND pressureValid AND pressure >= 4500.0 AND outletCmd >= 50 AND outletFeedback <= 10).
                    Any break (feedback OK, pressure < 4500, pressureValid=FALSE, runRequest=FALSE) → counter = 0.
   PUB015-PUB017:  latchedCauseMask accumulates via bitwise OR each scan tripLatched is TRUE (16-bit WORD, max 15, no overflow).
                    Cleared only on legal reset. Reflects full trip history, not a snapshot.
   PUB018-PUB020:  fuelPermit = runRequest AND NOT tripLatched; diagnosticActive = (currentCauseMask <> 0).
   PUB021-PUB023:  Clue encodings: 0=none, 1=xmitter fail, 2=stick only, 4=combustion only, 6=both, 8=unlocated.
   Units: kPa (pressure), t/h (flow), % (valve).
*)
FUNCTION_BLOCK FB
VAR
    prevResetBtn      : BOOL := FALSE;
    prevStickingCond1 : BOOL := FALSE;
    prevStickingCond2 : BOOL := FALSE;
    stickingCount     : INT  := 0;
    local_tripLatched : BOOL := FALSE;
    local_fuelPermit  : BOOL := FALSE;
    local_currentMask : WORD := 16#0000;
    local_latchedMask : WORD := 16#0000;
END_VAR
VAR_TEMP
    resetRising   : BOOL;
    curSticking   : BOOL;
END_VAR

    resetRising := resetBtn AND NOT prevResetBtn;

    IF resetRising AND NOT runRequest AND pressureValid AND (pressure <= 4200.0) THEN
        local_tripLatched := FALSE;
        local_latchedMask := 16#0000;
    ELSIF runRequest AND (NOT pressureValid OR (pressure >= 4500.0)) THEN
        local_tripLatched := TRUE;
    END_IF;

    curSticking := runRequest AND pressureValid AND (pressure >= 4500.0) AND (outletCmd >= 50) AND (outletFeedback <= 10);

    IF curSticking THEN
        IF prevStickingCond1 AND prevStickingCond2 THEN
            stickingCount := 3;
        ELSE
            stickingCount := stickingCount + 1;
            IF stickingCount > 3 THEN
                stickingCount := 3;
            END_IF;
        END_IF;
    ELSE
        stickingCount := 0;
    END_IF;

    local_currentMask := 16#0000;

    IF NOT runRequest THEN
        local_currentMask := 16#0000;
    ELSIF NOT pressureValid THEN
        local_currentMask := 16#0001;
    ELSE
        IF pressure >= 4500.0 THEN
            IF stickingCount >= 3 THEN
                local_currentMask := local_currentMask OR TO_WORD(2);
            END_IF;
            IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
                local_currentMask := local_currentMask OR TO_WORD(4);
            END_IF;
            IF (stickingCount < 3) AND NOT ((fuelFlow >= 4.0) AND (steamFlow <= 10.0)) THEN
                local_currentMask := local_currentMask OR TO_WORD(8);
            END_IF;
        END_IF;
    END_IF;

    IF local_tripLatched THEN
        local_latchedMask := local_latchedMask OR local_currentMask;
    END_IF;

    local_fuelPermit := runRequest AND NOT local_tripLatched;

    tripLatched      := local_tripLatched;
    fuelPermit       := local_fuelPermit;
    currentCauseMask := local_currentMask;
    latchedCauseMask := local_latchedMask;
    diagnosticActive := (local_currentMask <> 16#0000);

    prevResetBtn      := resetBtn;
    prevStickingCond2 := prevStickingCond1;
    prevStickingCond1 := curSticking;

END_FUNCTION_BLOCK