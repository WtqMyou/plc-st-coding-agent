FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    resetBtn    : BOOL;
    doneSensor  : BOOL;
    targetVol   : REAL;
    flowVol     : REAL;
END_VAR
VAR_OUTPUT
    valveOpen   : BOOL;
    fillsToday  : INT;
END_VAR
VAR
    prevStartBtn    : BOOL := FALSE;
    prevResetBtn    : BOOL := FALSE;
    prevValveOpen   : BOOL := FALSE;
    prevFillsToday  : INT  := 0;
    currentVolume   : REAL := 0.0;
    pendingConfirm  : BOOL := FALSE;
END_VAR
BEGIN
    // Reset takes absolute priority
    IF resetBtn AND NOT prevResetBtn THEN
        valveOpen      := FALSE;
        currentVolume  := 0.0;
        pendingConfirm := FALSE;
        fillsToday     := 0;
        prevFillsToday := 0;
    ELSIF startBtn AND NOT prevStartBtn THEN
        // New bottle starts
        pendingConfirm := FALSE;
        currentVolume  := flowVol;
        valveOpen      := TRUE;
        // Self-resetting: if this single shot already meets target
        IF currentVolume >= targetVol THEN
            valveOpen      := FALSE;
            pendingConfirm := FALSE;
            IF doneSensor THEN
                IF fillsToday < INT#32767 THEN
                    fillsToday := fillsToday + INT#1;
                END_IF;
            ELSE
                pendingConfirm := TRUE;
            END_IF;
        END_IF;
    ELSIF valveOpen THEN
        // Currently filling: accumulate flow
        currentVolume := currentVolume + flowVol;
        IF currentVolume >= targetVol THEN
            valveOpen      := FALSE;
            pendingConfirm := FALSE;
            IF doneSensor THEN
                IF fillsToday < INT#32767 THEN
                    fillsToday := fillsToday + INT#1;
                END_IF;
            ELSE
                pendingConfirm := TRUE;
            END_IF;
        END_IF;
    ELSIF pendingConfirm THEN
        // Waiting for sensor confirmation
        valveOpen := FALSE;
        IF doneSensor THEN
            IF fillsToday < INT#32767 THEN
                fillsToday := fillsToday + INT#1;
            END_IF;
            pendingConfirm := FALSE;
        END_IF;
    ELSE
        // Idle, nothing pending
        valveOpen := FALSE;
    END_IF;

    // Update edge detectors for next scan
    prevStartBtn   := startBtn;
    prevResetBtn   := resetBtn;
    prevValveOpen  := valveOpen;
    prevFillsToday := fillsToday;
END_FUNCTION_BLOCK