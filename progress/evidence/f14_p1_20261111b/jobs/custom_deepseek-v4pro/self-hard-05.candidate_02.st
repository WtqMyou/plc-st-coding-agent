FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    flameOK : BOOL;
    o2Valid : BOOL;
    o2PV : REAL;
    baseAir : REAL;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    fuelPermit : BOOL;
    trimEnable : BOOL;
    airTrim : REAL;
    airCommand : REAL;
    tripLatched : BOOL;
    o2Fault : BOOL;
END_VAR
VAR
    tripState : BOOL := FALSE;   (* internal trip memory *)
    prevReset : BOOL := FALSE;   (* previous cycle reset button state *)
    resetRising : BOOL;          (* reset rising edge flag *)
    rawTrim : REAL;              (* unclamped oxygen trim *)
END_VAR
BEGIN
    (* 1. Analyzer fault detection *)
    o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);

    (* 2. Reset button rising edge detection *)
    resetRising := resetBtn AND (NOT prevReset);

    (* 3. Trip state update (immediate set, self-holding with edge-clear) *)
    IF (runRequest AND (NOT flameOK)) THEN
        tripState := TRUE;
    ELSIF (tripState AND resetRising AND (NOT runRequest) AND (NOT flameOK)) THEN
        tripState := FALSE;
    END_IF;

    (* 4. Output latched trip *)
    tripLatched := tripState;

    (* 5. Fuel permit *)
    fuelPermit := runRequest AND flameOK AND (NOT tripLatched);

    (* 6. Oxygen trim enable *)
    trimEnable := fuelPermit AND (NOT o2Fault);

    (* 7. Oxygen trim calculation *)
    IF trimEnable THEN
        rawTrim := 2.0 * (2.0 - o2PV);
        IF rawTrim < -10.0 THEN
            airTrim := -10.0;
        ELSIF rawTrim > 10.0 THEN
            airTrim := 10.0;
        ELSE
            airTrim := rawTrim;
        END_IF;
    ELSE
        airTrim := 0.0;
    END_IF;

    (* 8. Air command calculation *)
    IF fuelPermit THEN
        airCommand := baseAir + airTrim;
        IF airCommand < 0.0 THEN
            airCommand := 0.0;
        ELSIF airCommand > 100.0 THEN
            airCommand := 100.0;
        END_IF;
    ELSE
        airCommand := 0.0;
    END_IF;

    (* 9. Store reset button state for next cycle edge detection *)
    prevReset := resetBtn;
END_FUNCTION_BLOCK