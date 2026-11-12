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
   Units: kPa (pressure), t/h (flow), % (valve), ms TON timers (not used; discrete-cycle counting).
*)
FUNCTION_BLOCK FB
VAR
    prevResetBtn      : BOOL := FALSE;   // PUB006: previous scan resetBtn for R_TRIG
    prevStickingCond1 : BOOL := FALSE;   // N10-S11: condition state at scan N-1
    prevStickingCond2 : BOOL := FALSE;   // N10-S11: condition state at scan N-2
    stickingCount     : INT  := 0;       // PUB012: consecutive-cycle counter (0..3)
END_VAR
VAR_OUTPUT
    tripLatched       : BOOL;
    fuelPermit        : BOOL;
    currentCauseMask  : WORD;
    latchedCauseMask  : WORD;
    diagnosticActive  : BOOL;
END_VAR

    // --- Rising-edge detection for reset button (PUB006) ---
    VAR temp_resetRising : BOOL;
    temp_resetRising := resetBtn AND NOT prevResetBtn;

    // --- Trip condition (PUB001-PUB004, S1, S2, S17) ---
    // Set: runRequest AND (NOT pressureValid OR pressure >= 4500.0)
    // Clear: rising resetBtn AND NOT runRequest AND pressureValid AND pressure <= 4200.0
    IF temp_resetRising AND NOT runRequest AND pressureValid AND (pressure <= 4200.0) THEN
        tripLatched := FALSE;
    ELSIF runRequest AND (NOT pressureValid OR (pressure >= 4500.0)) THEN
        tripLatched := TRUE;
    END_IF;

    // --- Valve sticking: 3 consecutive cycles under valid overpressure (PUB012-PUB014, N10-S11) ---
    // Condition: runRequest AND pressureValid AND pressure >= 4500.0 AND outletCmd >= 50 AND outletFeedback <= 10
    IF runRequest AND pressureValid AND (pressure >= 4500.0) AND (outletCmd >= 50) AND (outletFeedback <= 10) THEN
        // All three cycles met: current + prev1 + prev2
        IF prevStickingCond1 AND prevStickingCond2 THEN
            stickingCount := 3;
        ELSE
            stickingCount := stickingCount + 1;
            IF stickingCount > 3 THEN
                stickingCount := 3;
            END_IF;
        END_IF;
    ELSE
        // Any break resets counter (PUB014: feedback OK / pressure drop / invalid / stop)
        stickingCount := 0;
    END_IF;

    // --- Current cause mask (PUB009-PUB011, S5, S6, S9-S12, N10-S10, N10-S11, N10-S15) ---
    currentCauseMask := 16#0000;

    IF NOT runRequest THEN
        // PUB009: Not runRequest → mask = 0
        currentCauseMask := 16#0000;
    ELSIF NOT pressureValid THEN
        // PUB010: bit0=1 Transmitter failure (worst-case trip, PUB001)
        currentCauseMask := 16#0001;
    ELSE
        // pressureValid = TRUE
        IF pressure >= 4500.0 THEN
            // Evaluate bit1 (valve sticking) and bit2 (excess combustion) only in overpressure工况 (PUB010)
            // bit1: 3 consecutive cycles
            IF stickingCount >= 3 THEN
                currentCauseMask := currentCauseMask OR INT_TO_WORD(2); // bit1=2
            END_IF;

            // bit2: Excess combustion
            IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
                currentCauseMask := currentCauseMask OR INT_TO_WORD(4); // bit2=4
            END_IF;

            // bit3=8: Unlocated (overpressure but neither bit1 nor bit2 set, PUB010)
            IF (stickingCount < 3) AND NOT ((fuelFlow >= 4.0) AND (steamFlow <= 10.0)) THEN
                currentCauseMask := currentCauseMask OR INT_TO_WORD(8); // bit3=8
            END_IF;
        END_IF;
        // pressure < 4500.0: no clues (S6, N10-S15)
    END_IF;

    // --- Latched cause mask accumulation (PUB015-PUB017, S13, N10-S18) ---
    // Accumulates full trip history via bitwise OR while tripLatched is TRUE
    IF tripLatched AND (currentCauseMask <> 16#0000) THEN
        latchedCauseMask := latchedCauseMask OR currentCauseMask;
    END_IF;

    // --- Outputs (PUB018-PUB020, S3, N10-S16) ---
    fuelPermit       := runRequest AND NOT tripLatched;
    diagnosticActive := (currentCauseMask <> 16#0000);

    // --- State propagation for next scan ---
    prevResetBtn      := resetBtn;
    prevStickingCond2 := prevStickingCond1;
    prevStickingCond1 := (runRequest AND pressureValid AND (pressure >= 4500.0) AND (outletCmd >= 50) AND (outletFeedback <= 10));

END_FUNCTION_BLOCK