FUNCTION_BLOCK FB
VAR_INPUT
    runRequest  : BOOL;
    flameOK     : BOOL;
    o2Valid     : BOOL;
    o2PV        : REAL;
    baseAir     : REAL;
    resetBtn    : BOOL;
END_VAR
VAR_OUTPUT
    fuelPermit  : BOOL;
    trimEnable  : BOOL;
    airTrim     : REAL;
    airCommand  : REAL;
    tripLatched : BOOL;
    o2Fault     : BOOL;
END_VAR
VAR
    tmp_reset_rising : BOOL;
    tmp_trip_set     : BOOL;
END_VAR
(* ENGINEERING_CONTRACT
 * Output: tripLatched
 *   - SET:   runRequest=TRUE AND flameOK=FALSE  → same scan, no delay  [PUB001]
 *   - HOLD:  once set, retained across scans until valid reset edge     [PUB016]
 *   - RESET: rising(resetBtn) AND runRequest=FALSE AND flameOK=FALSE    [PUB016]
 *   - Edge-only reset; hold/rescan does NOT clear; press without edge does NOT clear
 * Output: fuelPermit
 *   - Activation:   runRequest AND flameOK AND NOT tripLatched          [PUB003]
 *   - Retention:    none — combinational, 0 when tripLatched           [PUB003]
 *   - Deactivation: tripLatched rising sets to FALSE; also 0 when any input low [PUB003]
 *   - Units: BOOLEAN
 * Output: trimEnable
 *   - Activation:   fuelPermit=TRUE AND o2Fault=FALSE                    [PUB008]
 *   - Retention:    none — combinational, 0 when o2Fault                [PUB008]
 *   - Deactivation: o2Fault rising (invalid/range)                      [PUB008]
 * Output: airTrim
 *   - Activation:   trimEnable with formula 2.0*(2.0-o2PV), clamp ±10   [PUB005]
 *   - Retention:    0.0 when trimEnable=FALSE (no residual)             [PUB010]
 *   - Units: % offset, clamped [-10,+10]
 * Output: airCommand
 *   - Activation:   baseAir+airTrim clamped [0,100] when fuelPermit=TRUE [PUB006]
 *   - Retention:    0.0 when fuelPermit=FALSE                           [PUB005]
 *   - Units: % absolute, clamped [0,100]; baseAir may be outside range [PUB006]
 * Output: o2Fault
 *   - Activation:   NOT o2Valid OR o2PV<0 OR o2PV>21                    [PUB009]
 *   - Retention:    combinational; does not inhibit fuelPermit          [PUB009]
 * Same-scan priority: trip set, fuelPermit, trimEnable/o2Fault, airTrim, airCommand
 * CONTRACT_RULES []
 *)
    // Detect rising edge of reset button (edge-only reset per PUB016)
    tmp_reset_rising := resetBtn AND NOT tmp_reset_rising;

    // Trip latch: set when running without flame, hold until valid reset edge
    tmp_trip_set := runRequest AND NOT flameOK;
    IF tmp_trip_set THEN
        tripLatched := TRUE;
    ELSIF tmp_reset_rising AND NOT runRequest AND NOT flameOK THEN
        tripLatched := FALSE;
    END_IF;

    // Fuel permit: requires run, flame, and no trip
    fuelPermit := runRequest AND flameOK AND NOT tripLatched;

    // O2 fault detection
    o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

    // Trim enable: fuel permit without O2 fault
    trimEnable := fuelPermit AND NOT o2Fault;

    // Air trim: 2.0*(2.0-o2PV), clamped to [-10, +10]; forced 0 when disabled
    IF trimEnable THEN
        airTrim := 2.0 * (2.0 - o2PV);
        IF airTrim > 10.0 THEN
            airTrim := 10.0;
        ELSIF airTrim < -10.0 THEN
            airTrim := -10.0;
        END_IF;
    ELSE
        airTrim := 0.0;
    END_IF;

    // Air command: base + trim, clamped [0,100]; forced 0 when no fuel permit
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
END_FUNCTION_BLOCK