FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    abortBtn : BOOL;
    setpoint : REAL;
    pv : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed : INT;
    phase : INT;
    timeout : BOOL;
END_VAR
VAR
    lastStart : BOOL;
    startRising : BOOL;
END_VAR

    startRising := startBtn AND NOT lastStart;
    lastStart := startBtn;

    IF startRising THEN
        phase := 1;
        elapsed := 0;
        timeout := FALSE;
    ELSE
        IF abortBtn THEN
            phase := 9;
        ELSE
            IF phase = 1 OR phase = 2 THEN
                elapsed := elapsed + 1;
                IF elapsed >= maxDuration THEN
                    timeout := TRUE;
                    phase := 3;
                ELSE
                    IF phase = 1 THEN
                        IF pv >= setpoint THEN
                            phase := 2;
                        END_IF;
                    END_IF;
                END_IF;
            END_IF;
        END_IF;
    END_IF;

END_FUNCTION_BLOCK