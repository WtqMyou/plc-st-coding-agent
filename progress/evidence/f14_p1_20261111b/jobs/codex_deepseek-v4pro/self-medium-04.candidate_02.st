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
    prevStartBtn : BOOL;
    prevResetBtn : BOOL;
    prevValveOpen : BOOL;
    bottleVol : REAL;
    pendingConfirm : BOOL;
    valveState : BOOL;
    fillCount : INT;
END_VAR

IF resetBtn AND NOT prevResetBtn THEN
    fillCount := 0;
    bottleVol := 0.0;
    valveState := FALSE;
    pendingConfirm := FALSE;
ELSE
    IF startBtn AND NOT prevStartBtn THEN
        IF NOT prevValveOpen THEN
            pendingConfirm := FALSE;
            bottleVol := 0.0;
            valveState := TRUE;
        END_IF;
    END_IF;

    IF valveState THEN
        bottleVol := bottleVol + flowVol;
        IF bottleVol >= targetVol THEN
            valveState := FALSE;
            pendingConfirm := TRUE;
        END_IF;
    END_IF;

    IF doneSensor AND pendingConfirm AND NOT valveState THEN
        IF fillCount < 32767 THEN
            fillCount := fillCount + 1;
        END_IF;
        pendingConfirm := FALSE;
    END_IF;
END_IF;

valveOpen := valveState;
fillsToday := fillCount;

prevStartBtn := startBtn;
prevResetBtn := resetBtn;
prevValveOpen := valveState;

END_FUNCTION_BLOCK