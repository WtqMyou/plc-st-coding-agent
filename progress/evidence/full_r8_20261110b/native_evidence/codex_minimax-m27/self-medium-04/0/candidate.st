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
    prevStartBtn  : BOOL := FALSE;
    prevResetBtn  : BOOL := FALSE;
    prevValveOpen : BOOL := FALSE;
    prevTargetVol : REAL := 0.0;
    accumulated   : REAL := 0.0;
    fillingDone   : BOOL := FALSE;
    state         : INT := 0; // 0=IDLE, 1=FILLING, 2=WAIT
END_VAR

VAR
    startBtnR  : BOOL;
    resetBtnR  : BOOL;
    valveCloseR: BOOL;
END_VAR

// Rising edge detection
startBtnR  := startBtn  AND NOT prevStartBtn;
resetBtnR  := resetBtn  AND NOT prevResetBtn;
valveCloseR:= prevValveOpen AND NOT valveOpen;

// Reset has highest priority
IF resetBtnR THEN
    valveOpen   := FALSE;
    fillsToday  := 0;
    accumulated := 0.0;
    fillingDone := FALSE;
    state       := 0;
ELSE
    CASE state OF
        0: // IDLE
            fillsToday := fillsToday; // hold
            accumulated := 0.0;
            fillingDone := FALSE;
            IF startBtnR THEN
                valveOpen := (flowVol < targetVol);
                accumulated := flowVol;
                IF flowVol >= targetVol THEN
                    state := 2; // WAIT
                    fillingDone := TRUE;
                ELSE
                    state := 1; // FILLING
                END_IF
            ELSE
                valveOpen := FALSE;
            END_IF

        1: // FILLING
            accumulated := accumulated + flowVol;
            IF accumulated >= targetVol THEN
                valveOpen   := FALSE;
                fillingDone := TRUE;
                state       := 2;
            ELSE
                valveOpen := TRUE;
            END_IF

        2: // WAIT for doneSensor confirmation
            valveOpen := FALSE;
            IF startBtnR THEN
                accumulated := flowVol;
                fillingDone := FALSE;
                IF flowVol >= targetVol THEN
                    state := 2;
                    fillingDone := TRUE;
                ELSE
                    valveOpen := (flowVol < targetVol);
                    state := 1;
                END_IF
            ELSIF doneSensor THEN
                IF fillsToday < 32767 THEN
                    fillsToday := fillsToday + 1;
                END_IF
                fillingDone := FALSE;
                state := 0;
            END_IF
    END_CASE
END_IF

// History update
prevStartBtn  := startBtn;
prevResetBtn  := resetBtn;
prevValveOpen := valveOpen;
prevTargetVol := targetVol;
END_FUNCTION_BLOCK