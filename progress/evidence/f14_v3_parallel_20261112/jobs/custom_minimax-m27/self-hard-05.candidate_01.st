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
    prevResetBtn : BOOL := FALSE;
END_VAR

    // Rising edge detection for reset button
    VAR
        resetRisingEdge : BOOL;
    END_VAR
    resetRisingEdge := resetBtn AND NOT prevResetBtn;
    prevResetBtn := resetBtn;

    // Trip latch: immediate set on flame loss during run; clear only on safe-state reset edge
    IF runRequest AND NOT flameOK THEN
        tripLatched := TRUE;
    ELSIF resetRisingEdge AND NOT runRequest AND NOT flameOK THEN
        tripLatched := FALSE;
    END_IF;

    // Fuel permit
    fuelPermit := runRequest AND flameOK AND NOT tripLatched;

    // O2 analyzer fault
    o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

    // Trim enable
    trimEnable := fuelPermit AND NOT o2Fault;

    // Air trim: compute and clamp to [-10, +10]; force 0 when trim not enabled
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

    // Air command: sum and clamp to [0, 100]; force 0 when no fuel permit
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