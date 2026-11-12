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
    startBtn_prev : BOOL;
    resetBtn_prev : BOOL;
    is_filling : BOOL;
    accumulated_volume : REAL;
    waiting_for_done : BOOL;
    start_rising : BOOL;
    reset_rising : BOOL;
END_VAR

start_rising := startBtn AND NOT startBtn_prev;
reset_rising := resetBtn AND NOT resetBtn_prev;

IF reset_rising THEN
    fillsToday := 0;
    valveOpen := FALSE;
    accumulated_volume := 0.0;
    waiting_for_done := FALSE;
    is_filling := FALSE;
ELSE
    IF start_rising AND NOT is_filling THEN
        waiting_for_done := FALSE;
        is_filling := TRUE;
        accumulated_volume := 0.0;
    END_IF;

    IF is_filling THEN
        accumulated_volume := accumulated_volume + flowVol;
        IF accumulated_volume >= targetVol THEN
            valveOpen := FALSE;
            is_filling := FALSE;
            waiting_for_done := TRUE;
        ELSE
            valveOpen := TRUE;
        END_IF;
    ELSE
        valveOpen := FALSE;
        IF waiting_for_done AND doneSensor THEN
            IF fillsToday < 32767 THEN
                fillsToday := fillsToday + 1;
            END_IF;
            waiting_for_done := FALSE;
        END_IF;
    END_IF;
END_IF;

startBtn_prev := startBtn;
resetBtn_prev := resetBtn;

END_FUNCTION_BLOCK
