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
    prevStartBtn      : BOOL := FALSE;
    prevResetBtn      : BOOL := FALSE;
    prevValveOpen     : BOOL := FALSE;
    currentVolume     : REAL := 0.0;
    pendingConfirm    : BOOL := FALSE;
    prevFillsToday    : INT  := 0;
END_VAR
VAR_TEMP
    risingStart  : BOOL;
    risingReset  : BOOL;
END_VAR
BEGIN
    risingStart  := startBtn AND NOT prevStartBtn;
    risingReset  := resetBtn AND NOT prevResetBtn;

    // Reset takes absolute priority
    IF risingReset THEN
        valveOpen      := FALSE;
        currentVolume  := 0.0;
        pendingConfirm := FALSE;
        fillsToday     := 0;
        prevFillsToday := 0;
    ELSIF risingStart THEN
        // New bottle starts
        pendingConfirm := FALSE;
        currentVolume  := flowVol;
        IF prevValveOpen THEN
            // Previous bottle still filling; cancel it, start new one
            valveOpen := TRUE;
        ELSE
            // Normal start from idle
            valveOpen := TRUE;
        END_IF;
        // Self-resetting: if this single shot already meets target
        IF currentVolume >= targetVol THEN
            valveOpen := FALSE;
            IF doneSensor THEN
                // Immediate confirmation same scan
                IF fillsToday < INT#32767 THEN
                    fillsToday := fillsToday + INT#1;
                END_IF;
                pendingConfirm := FALSE;
            ELSE
                pendingConfirm := TRUE;
            END_IF;
        END_IF;
    ELSIF valveOpen THEN
        // Currently filling: accumulate flow
        currentVolume := currentVolume + flowVol;
        IF currentVolume >= targetVol THEN
            valveOpen := FALSE;
            IF doneSensor THEN
                // Target met and sensor already true → confirm immediately
                IF fillsToday < INT#32767 THEN
                    fillsToday := fillsToday + INT#1;
                END_IF;
                pendingConfirm := FALSE;
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
    prevStartBtn  := startBtn;
    prevResetBtn  := resetBtn;
    prevValveOpen := valveOpen;
    prevFillsToday := fillsToday;
END_FUNCTION_BLOCK