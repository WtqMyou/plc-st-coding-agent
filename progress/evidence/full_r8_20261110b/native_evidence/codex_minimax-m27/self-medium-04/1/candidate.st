FUNCTION_BLOCK FB
VAR_INPUT
    startBtn   : BOOL;
    resetBtn   : BOOL;
    doneSensor : BOOL;
    targetVol  : REAL;
    flowVol    : REAL;
END_VAR
VAR_OUTPUT
    valveOpen  : BOOL;
    fillsToday : INT;
END_VAR
VAR
    prevStartBtn   : BOOL := FALSE;
    prevResetBtn   : BOOL := FALSE;
    prevValveOpen  : BOOL := FALSE;
    accumulated    : REAL := 0.0;
    fillingDone    : BOOL := FALSE;
    state          : INT := 0;
END_VAR

VAR
    startBtnR  : BOOL;
    resetBtnR  : BOOL;
END_VAR

startBtnR := startBtn AND NOT prevStartBtn;
resetBtnR := resetBtn AND NOT prevResetBtn;

IF resetBtnR THEN
    valveOpen   := FALSE;
    fillsToday  := 0;
    accumulated := 0.0;
    fillingDone := FALSE;
    state       := 0;
ELSE
    CASE state OF
        0:
            accumulated := 0.0;
            IF startBtnR THEN
                valveOpen   := (flowVol < targetVol);
                accumulated := flowVol;
                IF flowVol >= targetVol THEN
                    state       := 2;
                    fillingDone := TRUE;
                ELSE
                    state := 1;
                END_IF;
            ELSE
                valveOpen := FALSE;
            END_IF;

        1:
            accumulated := accumulated + flowVol;
            IF accumulated >= targetVol THEN
                valveOpen   := FALSE;
                fillingDone := TRUE;
                state       := 2;
            ELSE
                valveOpen := TRUE;
            END_IF;

        2:
            valveOpen := FALSE;
            IF doneSensor THEN
                fillsToday := MIN(fillsToday + 1, 32767);
                fillingDone := FALSE;
                state := 0;
            ELSIF startBtnR THEN
                accumulated := flowVol;
                fillingDone := FALSE;
                IF flowVol >= targetVol THEN
                    state       := 2;
                    fillingDone := TRUE;
                ELSE
                    valveOpen := (flowVol < targetVol);
                    state := 1;
                END_IF;
            END_IF;
    END_CASE;
END_IF;

prevStartBtn  := startBtn;
prevResetBtn  := resetBtn;
prevValveOpen := valveOpen;
END_FUNCTION_BLOCK