(* ENGINEERING_CONTRACT
 * FSM: Flame-trip latch with edge-reset.
 * [PUB001,PUB003] tripLatched activates SAME SCAN on (runRequest & !flameOK).
 * [PUB007] tripLatched holds until rising(resetBtn) & (!runRequest) & (!flameOK).
 *   Reset is edge-only; holding reset or pressing it under any other condition has no effect.
 * [PUB002,PUB004,PUB006] fuelPermit = runRequest & flameOK & !tripLatched (all three required).
 * [PUB005] o2Fault = !o2Valid OR o2PV<0 OR o2PV>21; fault removes trim only, never fuel.
 * [PUB008] trimEnable = fuelPermit & !o2Fault.
 * [PUB008,PUB030,PUB046] airTrim = 2.0*(2.0-o2PV) clamped [-10,+10]; 0 when trimEnable=FALSE.
 *   Positive limit never triggers (raw range [−38,+4] within o2PV∈[0,21]).
 * [PUB009,PUB031,PUB047] airCommand = baseAir+airTrim clamped [0,100]; 0 when fuelPermit=FALSE.
 *   baseAir may be outside [0,100]; final clamp applies to the sum only.
 *
 * LTL coverage:
 * S1  tripLatched on same-scan flame loss         → G((runRequest & !flameOK) → tripLatched)
 * S2  Self-hold; reset is edge-only               → G((prev(tripLatched) & !(rising & safe)) → tripLatched)
 * S3  tripLatched blocks fuel                     → G(tripLatched → !fuelPermit)
 * S4  fuelPermit full definition                  → G(fuelPermit ↔ runRequest & flameOK & !tripLatched)
 * S5  No fuel → airCommand=0                      → G(!fuelPermit → airCommand=0)
 * S6  airCommand ∈ [0,100]                        → G(airCommand≥0 ∧ airCommand≤100)
 * S7  airTrim ∈ [−10,10]                          → G(airTrim≥−10 ∧ airTrim≤10)
 * S8  trimEnable full definition                  → G(trimEnable ↔ fuelPermit & !o2Fault)
 * S9  o2Fault definition                          → G(o2Fault ↔ !o2Valid ∨ o2PV<0 ∨ o2PV>21)
 * S10 trimDisable → airTrim=0                     → G(!trimEnable → airTrim=0)
 * S11 o2PV>7 → negative clamp fires               → G((trimEnable & o2PV>7) → airTrim=−10)
 * S12 o2PV≤7 → no clamping                        → G((trimEnable & o2PV≤7) → airTrim=2*(2−o2PV))
 * S13 sum>100 → clamp to 100                      → G((fuelPermit & baseAir+airTrim>100) → airCommand=100)
 * S14 sum<0   → clamp to 0                        → G((fuelPermit & baseAir+airTrim<0)   → airCommand=0)
 * N10-S16 trip latch complete FSM                 → G(tripLatched ↔ (runRequest∧!flameOK)∨(prev∧!resetEdge)))
 * N10-S17 in-range sum is passed through          → G((fuelPermit & inRange) → airCommand=baseAir+airTrim)
 *
 * CONTRACT_RULES [{"kind":"hold_until_reset","output":"tripLatched","set_input":"runRequest","reset_input":"resetBtn"},{"kind":"hold_until_reset","output":"tripLatched","set_input":"flameOK","reset_input":"resetBtn"}]
 *)

FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    flameOK    : BOOL;
    o2Valid    : BOOL;
    o2PV       : REAL;
    baseAir    : REAL;
    resetBtn   : BOOL;
END_VAR
VAR_OUTPUT
    fuelPermit : BOOL;
    trimEnable : BOOL;
    airTrim    : REAL;
    airCommand : REAL;
    tripLatched: BOOL;
    o2Fault    : BOOL;
END_VAR
VAR
    prev_resetBtn   : BOOL := FALSE;
    prev_tripLatched: BOOL := FALSE;
END_VAR

    // --- Edge detection (same-scan memory) ---
    // Rising edge of resetBtn: was FALSE last scan, is TRUE this scan.
    // Store previous states at end of this scan for next invocation.

    // --- Flame-trip latch (PUB001,PUB003,PUB007) ---
    // Set on same scan when runRequest=TRUE and flameOK=FALSE.
    // Clear only on rising(resetBtn) AND runRequest=FALSE AND flameOK=FALSE.
    // Reset is edge-triggered; level-hold of resetBtn does NOT clear.
    IF runRequest AND NOT flameOK THEN
        tripLatched := TRUE;
    ELSIF prev_resetBtn = FALSE AND resetBtn = TRUE
          AND NOT runRequest AND NOT flameOK THEN
        tripLatched := FALSE;
    ELSE
        tripLatched := prev_tripLatched;
    END_IF;

    // --- Fuel permit (PUB002,PUB004,PUB006) ---
    fuelPermit := runRequest AND flameOK AND NOT tripLatched;

    // --- O2 fault detection (PUB005) ---
    o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

    // --- O2 trim correction (PUB008,PUB030,PUB046) ---
    trimEnable := fuelPermit AND NOT o2Fault;

    IF trimEnable THEN
        // Formula: 2.0 * (2.0 - o2PV), clamped to [-10, +10]
        // Within valid o2PV range [0,21] raw result lies in [-38, +4];
        // positive limit never triggers; negative limit fires when o2PV > 7.0.
        airTrim := 2.0 * (2.0 - o2PV);
        IF airTrim > 10.0 THEN
            airTrim := 10.0;
        ELSIF airTrim < -10.0 THEN
            airTrim := -10.0;
        END_IF;
    ELSE
        airTrim := 0.0;
    END_IF;

    // --- Air command (PUB009,PUB031,PUB047) ---
    // baseAir is external setpoint; may lie outside [0,100].
    // fuelPermit=FALSE forces airCommand to 0 (no residual position).
    IF fuelPermit THEN
        airCommand := baseAir + airTrim;
        IF airCommand > 100.0 THEN
            airCommand := 100.0;
        ELSIF airCommand < 0.0 THEN
            airCommand := 0.0;
        END_IF;
    ELSE
        airCommand := 0.0;
    END_IF;

    // --- Same-scan state update (persist for next scan) ---
    prev_resetBtn    := resetBtn;
    prev_tripLatched := tripLatched;
END_FUNCTION_BLOCK