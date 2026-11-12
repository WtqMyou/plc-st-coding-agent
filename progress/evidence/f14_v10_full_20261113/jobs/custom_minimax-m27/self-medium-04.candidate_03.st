FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    resetBtn    : BOOL;
    doneSensor  : BOOL;
    targetVol   : REAL;
    flowVol     : REAL;
END_VAR
VAR_OUTPUT
    valveOpen   : BOOL := FALSE;
    fillsToday  : INT  := 0;
END_VAR
VAR
    state           : INT := 0; // 0=IDLE, 1=FILLING, 2=WAIT_CONFIRM
    accumulated     : REAL := 0.0;
    pendingConfirm  : BOOL := FALSE;
    prevStartBtn    : BOOL := FALSE;
    prevResetBtn    : BOOL := FALSE;
    prevValveOpen   : BOOL := FALSE;
    R_TRIG_reset    : R_TRIG;
    R_TRIG_start    : R_TRIG;
END_VAR
BEGIN
    // --- Step 1: Reset (highest priority) ---
    R_TRIG_reset(CLK := resetBtn);
    IF R_TRIG_reset.Q THEN
        accumulated    := 0.0;
        fillsToday     := 0;
        valveOpen      := FALSE;
        pendingConfirm := FALSE;
        state          := 0; // IDLE
    ELSE
        // --- Step 2: Start new bottle ---
        R_TRIG_start(CLK := startBtn);
        IF R_TRIG_start.Q THEN
            IF state = 2 THEN // WAIT_CONFIRM
                pendingConfirm := FALSE;
            END_IF;
            IF state <> 1 THEN // not FILLING
                accumulated := 0.0;
                valveOpen   := TRUE;
                state       := 1; // FILLING
            END_IF;
        END_IF;
        
        // --- Step 3: Accumulate and close on target ---
        IF state = 1 THEN // FILLING
            accumulated := accumulated + flowVol;
            IF accumulated >= targetVol THEN
                valveOpen      := FALSE;
                pendingConfirm := TRUE;
                state          := 2; // WAIT_CONFIRM
            END_IF;
        END_IF;
        
        // --- Step 4: Confirm/count (same-scan or deferred) ---
        IF prevValveOpen AND NOT valveOpen AND pendingConfirm THEN
            // Valve just closed this scan
            IF doneSensor THEN
                IF fillsToday < 32767 THEN
                    fillsToday := fillsToday + 1;
                END_IF;
                pendingConfirm := FALSE;
                state          := 0; // IDLE
            END_IF;
        ELSIF pendingConfirm AND doneSensor THEN
            // S10: Valve closed last scan, confirmed this scan
            IF fillsToday < 32767 THEN
                fillsToday := fillsToday + 1;
            END_IF;
            pendingConfirm := FALSE;
            state          := 0; // IDLE
        END_IF;
    END_IF;
    
    prevStartBtn  := startBtn;
    prevResetBtn  := resetBtn;
    prevValveOpen := valveOpen;
END_FUNCTION_BLOCK