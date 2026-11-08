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
    eState       : INT;     // 0=IDLE, 1=FILLING, 2=WAITING_CONFIRM
    accumulator  : REAL;
    lastStartBtn : BOOL;
    lastResetBtn : BOOL;
    risingStart  : BOOL;
    risingReset  : BOOL;
END_VAR

    // ---- Edge detection -------------------------------------------------
    risingStart := startBtn AND NOT lastStartBtn;
    risingReset := resetBtn AND NOT lastResetBtn;

    // ---- Reset handling (highest priority) -------------------------------
    IF risingReset THEN
        valveOpen   := FALSE;
        accumulator := 0.0;
        fillsToday  := 0;
        eState      := 0;    // IDLE
    ELSE
        // ---- State machine -----------------------------------------------
        CASE eState OF
            0:  // IDLE
                IF risingStart THEN
                    valveOpen   := TRUE;
                    accumulator := 0.0;
                    eState      := 1;  // FILLING
                ELSE
                    valveOpen := FALSE;
                END_IF

            1:  // FILLING
                accumulator := accumulator + flowVol;
                IF accumulator >= targetVol THEN
                    valveOpen := FALSE;
                    eState    := 2;    // WAITING_CONFIRM
                END_IF

            2:  // WAITING_CONFIRM
                valveOpen := FALSE;
                IF doneSensor THEN
                    fillsToday := fillsToday + 1;
                    eState     := 0;    // IDLE
                END_IF
        END_CASE
    END_IF

    // ---- Update edge histories --------------------------------------------
    lastStartBtn := startBtn;
    lastResetBtn := resetBtn;

END_FUNCTION_BLOCK