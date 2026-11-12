TYPE ETripStickingState :
(
   ST_CLEAR := 0,
   ST_COUNT1 := 1,
   ST_COUNT2 := 2,
   ST_CONFIRMED := 3
);
END_TYPE;

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
    stickingCounter  : UINT := 0;
    prevResetBtn     : BOOL := FALSE;
END_VAR
VAR_TEMP
    risingEdgeReset : BOOL;
    validReset      : BOOL;
    tripCondition   : BOOL;
    condSticking    : BOOL;
    stuckConfirmed  : BOOL;
    bit2            : BOOL;
END_VAR

    risingEdgeReset := resetBtn AND NOT prevResetBtn;

    validReset := risingEdgeReset
                  AND (NOT runRequest)
                  AND pressureValid
                  AND (pressure <= 4200.0);

    IF validReset THEN
        tripLatched      := FALSE;
        latchedCauseMask := 0;
    ELSE
        tripCondition := runRequest AND (NOT pressureValid OR pressure >= 4500.0);
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
                    AND (pressure >= 4500.0)
                    AND (outletCmd >= 50)
                    AND (outletFeedback <= 10);

    IF condSticking THEN
        IF stickingCounter < 16#FFFF THEN
            stickingCounter := stickingCounter + 1;
        END_IF;
    ELSE
        stickingCounter := 0;
    END_IF;

    stuckConfirmed := (stickingCounter >= 3) AND prevCondSticking;

    bit2 := (fuelFlow >= 4.0) AND (steamFlow <= 10.0);

    IF NOT runRequest THEN
        currentCauseMask := 0;
    ELSIF NOT pressureValid THEN
        currentCauseMask := 1;
    ELSIF pressure >= 4500.0 THEN
        currentCauseMask := TO_WORD(
            TO_INT(stuckConfirmed) * 2 +
            TO_INT(bit2) * 4 +
            TO_INT(NOT stuckConfirmed AND NOT bit2) * 8
        );
    ELSE
        currentCauseMask := 0;
    END_IF;

    diagnosticActive := (currentCauseMask <> 0);

    prevCondSticking := condSticking;
    prevResetBtn     := resetBtn;
END_FUNCTION_BLOCK