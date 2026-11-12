TYPE ETripStickingState :
(
   ST_CLEAR := 0,
   ST_COUNT1 := 1,
   ST_COUNT2 := 2,
   ST_CONFIRMED := 3
);
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    runRequest       : BOOL;
    pressure         : REAL;
    pressureValid    : BOOL;
    fuelFlow         : REAL;
    steamFlow        : REAL;
    outletCmd        : INT;
    outletFeedback   : INT;
    resetBtn         : BOOL;
END_VAR
VAR_OUTPUT
    tripLatched      : BOOL;
    fuelPermit       : BOOL;
    currentCauseMask : WORD;
    latchedCauseMask : WORD;
    diagnosticActive : BOOL;
END_VAR
VAR
    prevCondSticking : BOOL := FALSE;
    stickingCounter  : UINT  := 0;
    prevResetBtn     : BOOL  := FALSE;
END_VAR
VAR_CONSTANT
    cPressureTrip     : REAL := 4500.0;
    cPressureReset    : REAL := 4200.0;
    cFuelFlowThreshold: REAL := 4.0;
    cSteamFlowThreshold: REAL := 10.0;
    cStickingCycles   : UINT := 3;
    cValveCmdMin      : INT  := 50;
    cValveFbkMax      : INT  := 10;
END_VAR
VAR_TEMP
    risingEdgeReset : BOOL;
    validReset      : BOOL;
    tripCondition   : BOOL;
    condSticking    : BOOL;
    bit0            : BOOL;
    bit1            : BOOL;
    bit2            : BOOL;
    bit3            : BOOL;
END_VAR

    risingEdgeReset := resetBtn AND NOT prevResetBtn;

    validReset := risingEdgeReset
                  AND NOT runRequest
                  AND pressureValid
                  AND (pressure <= cPressureReset);

    IF validReset THEN
        tripLatched      := FALSE;
        latchedCauseMask := 0;
    ELSE
        tripCondition := runRequest AND (NOT pressureValid OR pressure >= cPressureTrip);
        IF tripCondition THEN
            tripLatched := TRUE;
        END_IF;
        IF tripLatched THEN
            latchedCauseMask := latchedCauseMask OR currentCauseMask;
        END_IF;
    END_IF;

    fuelPermit := runRequest AND NOT tripLatched;

    condSticking := runRequest
                    AND pressureValid
                    AND (pressure >= cPressureTrip)
                    AND (outletCmd >= cValveCmdMin)
                    AND (outletFeedback <= cValveFbkMax);

    IF condSticking THEN
        IF stickingCounter < cStickingCycles THEN
            stickingCounter := stickingCounter + 1;
        END_IF;
    ELSE
        stickingCounter := 0;
    END_IF;

    prevCondSticking := condSticking;

    IF NOT runRequest THEN
        currentCauseMask := 0;
    ELSIF NOT pressureValid THEN
        currentCauseMask := 1;
    ELSIF pressure >= cPressureTrip THEN
        bit0 := FALSE;
        bit1 := (stickingCounter >= cStickingCycles)
                AND prevCondSticking;
        bit2 := (fuelFlow >= cFuelFlowThreshold)
                AND (steamFlow <= cSteamFlowThreshold);
        bit3 := NOT bit1 AND NOT bit2;
        currentCauseMask := TO_WORD(
            TO_INT(bit0) +
            TO_INT(bit1) * 2 +
            TO_INT(bit2) * 4 +
            TO_INT(bit3) * 8
        );
    ELSE
        currentCauseMask := 0;
    END_IF;

    diagnosticActive := (currentCauseMask <> 0);

    prevResetBtn := resetBtn;
END_FUNCTION_BLOCK