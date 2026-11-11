FUNCTION_BLOCK FB
VAR_INPUT
    demand     : INT;
    runHours   : ARRAY[1..5] OF LINT;
    rotated    : BOOL;
END_VAR

VAR_OUTPUT
    leadPump      : INT := 0;
    lagPump       : INT := 0;
    runningCount  : INT := 0;
END_VAR

VAR
    prevDemand       : INT := 0;
    prevLeadPump     : INT := 0;
    prevRunningCount : INT := 0;
    clampedDemand    : INT;
    minHrs           : LINT;
    minPump          : INT;
    i                : INT;
END_VAR

clampedDemand := demand;
IF clampedDemand < 0 THEN
    clampedDemand := 0;
END_IF
IF clampedDemand > 5 THEN
    clampedDemand := 5;
END_IF

runningCount := clampedDemand;

IF clampedDemand = 0 THEN
    leadPump := 0;
    lagPump := 0;
    prevDemand := 0;
    prevLeadPump := 0;
    prevRunningCount := 0;
ELSIF prevLeadPump = 0 THEN
    minHrs := runHours[1];
    minPump := 1;
    FOR i := 2 TO 5 DO
        IF runHours[i] < minHrs OR (runHours[i] = minHrs AND i < minPump) THEN
            minHrs := runHours[i];
            minPump := i;
        END_IF
    END_FOR
    leadPump := minPump;
    
    IF clampedDemand >= 2 THEN
        minHrs := LINT#16#7FFFFFFFFFFFFFFF;
        minPump := 0;
        FOR i := 1 TO 5 DO
            IF i <> leadPump THEN
                IF runHours[i] < minHrs OR (runHours[i] = minHrs AND i < minPump) THEN
                    minHrs := runHours[i];
                    minPump := i;
                END_IF
            END_IF
        END_FOR
        lagPump := minPump;
    END_IF
ELSE
    minHrs := runHours[1];
    minPump := 1;
    FOR i := 2 TO 5 DO
        IF runHours[i] < minHrs OR (runHours[i] = minHrs AND i < minPump) THEN
            minHrs := runHours[i];
            minPump := i;
        END_IF
    END_FOR
    
    IF rotated AND runHours[leadPump] - minHrs > 50 THEN
        leadPump := minPump;
    END_IF
    
    IF clampedDemand >= 2 THEN
        IF lagPump = 0 THEN
            minHrs := LINT#16#7FFFFFFFFFFFFFFF;
            minPump := 0;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF runHours[i] < minHrs OR (runHours[i] = minHrs AND i < minPump) THEN
                        minHrs := runHours[i];
                        minPump := i;
                    END_IF
                END_IF
            END_FOR
            lagPump := minPump;
        ELSIF leadPump <> prevLeadPump OR clampedDemand > prevRunningCount THEN
            minHrs := LINT#16#7FFFFFFFFFFFFFFF;
            minPump := 0;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF runHours[i] < minHrs OR (runHours[i] = minHrs AND i < minPump) THEN
                        minHrs := runHours[i];
                        minPump := i;
                    END_IF
                END_IF
            END_FOR
            lagPump := minPump;
        END_IF
    ELSIF lagPump <> 0 THEN
        lagPump := 0;
    END_IF
END_IF

prevDemand := clampedDemand;
prevLeadPump := leadPump;
prevRunningCount := clampedDemand;

END_FUNCTION_BLOCK