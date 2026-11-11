FUNCTION_BLOCK FB
VAR_INPUT
    startBtn   : BOOL;
    abortBtn   : BOOL;
    setpoint   : REAL;
    pv         : REAL;
    maxDuration: INT;
END_VAR
VAR_OUTPUT
    elapsed : INT;
    phase   : INT;
    timeout : BOOL;
END_VAR
VAR
    lastStartBtn : BOOL := FALSE;
    prevPhase    : INT  := 0;
    prevElapsed  : INT  := 0;
    prevTimeout  : BOOL := FALSE;
END_VAR
VAR
    risingStart : BOOL;
    newPhase    : INT;
    newElapsed  : INT;
    newTimeout  : BOOL;
END_VAR

risingStart := startBtn AND NOT lastStartBtn;

IF abortBtn THEN
    newPhase   := 9;
    newElapsed := prevElapsed;
    newTimeout := prevTimeout;
ELSE
    IF risingStart THEN
        newPhase   := 1;
        newElapsed := 0;
        newTimeout := FALSE;
    ELSE
        IF (prevPhase = 1) OR (prevPhase = 2) THEN
            newElapsed := prevElapsed + 1;

            IF newElapsed >= maxDuration THEN
                newTimeout := TRUE;
                newPhase   := 3;
            ELSE
                newTimeout := prevTimeout;

                IF prevPhase = 1 THEN
                    IF pv >= setpoint THEN
                        newPhase := 2;
                    ELSE
                        newPhase := 1;
                    END_IF
                ELSE
                    newPhase := 2;
                END_IF;
            END_IF;
        ELSE
            newPhase   := prevPhase;
            newElapsed := prevElapsed;
            newTimeout := prevTimeout;
        END_IF;
    END_IF;
END_IF;

elapsed := newElapsed;
phase   := newPhase;
timeout := newTimeout;

prevPhase   := newPhase;
prevElapsed := newElapsed;
prevTimeout := newTimeout;

lastStartBtn := startBtn;
END_FUNCTION_BLOCK