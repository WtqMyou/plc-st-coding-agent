FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    resetBtn : BOOL;
    doneSensor : BOOL;
    targetVol : REAL;
    flowVol : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;
    fillsToday : INT;
END_VAR
VAR
    prevStartBtn : BOOL := FALSE;
    prevResetBtn : BOOL := FALSE;
    prevValveOpen : BOOL := FALSE;
    accumulatedVolume : REAL := 0.0;
    pendingConfirm : BOOL := FALSE;
    startEdge : BOOL;
    resetEdge : BOOL;
    fillingNow : BOOL;
END_VAR

startEdge := startBtn AND NOT prevStartBtn;
resetEdge := resetBtn AND NOT prevResetBtn;

IF resetEdge THEN
    fillsToday := 0;
    accumulatedVolume := 0.0;
    pendingConfirm := FALSE;
    valveOpen := FALSE;
ELSE
    fillingNow := prevValveOpen;

    IF startEdge AND NOT prevValveOpen THEN
        pendingConfirm := FALSE;
        accumulatedVolume := 0.0;
        valveOpen := TRUE;
        fillingNow := TRUE;
    END_IF;

    IF fillingNow THEN
        accumulatedVolume := accumulatedVolume + flowVol;

        IF accumulatedVolume >= targetVol THEN
            valveOpen := FALSE;
            pendingConfirm := TRUE;
        ELSE
            valveOpen := TRUE;
        END_IF;
    END_IF;

    IF pendingConfirm AND doneSensor AND NOT valveOpen THEN
        IF fillsToday < 32767 THEN
            fillsToday := fillsToday + 1;
        END_IF;
        pendingConfirm := FALSE;
    END_IF;
END_IF;

prevStartBtn := startBtn;
prevResetBtn := resetBtn;
prevValveOpen := valveOpen;
END_FUNCTION_BLOCK