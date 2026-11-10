FUNCTION_BLOCK FB
VAR_INPUT
    demand        : INT;
    runHours      : ARRAY[1..5] OF LINT;
    rotated       : BOOL;
END_VAR
VAR_OUTPUT
    leadPump      : INT := 0;
    lagPump       : INT := 0;
    runningCount  : INT := 0;
END_VAR
VAR
    prevDemand        : INT := 0;
    prevRunningCount  : INT := 0;
    prevLeadPump      : INT := 0;
    prevLagPump       : INT := 0;
    hadValidLeadPump  : BOOL := FALSE;
    minHours          : LINT;
    minPumpIdx        : INT;
    i                 : INT;
    tempMinHours      : LINT;
    tempMinPumpIdx    : INT;
    needReselect      : BOOL;
END_VAR

runningCount := demand;
IF demand < 0 THEN
    runningCount := 0;
ELSIF demand > 5 THEN
    runningCount := 5;
END_IF;

IF runningCount = 0 THEN
    leadPump := 0;
    lagPump  := 0;
ELSE
    IF (NOT hadValidLeadPump) OR (prevDemand = 0) THEN
        minHours     := runHours[1];
        minPumpIdx   := 1;
        FOR i := 2 TO 5 DO
            IF runHours[i] < minHours OR (runHours[i] = minHours AND i < minPumpIdx) THEN
                minHours   := runHours[i];
                minPumpIdx := i;
            END_IF;
        END_FOR;
        leadPump := minPumpIdx;
        IF runningCount >= 2 THEN
            tempMinHours     := LINT#16#7FFFFFFFFFFFFFFF;
            tempMinPumpIdx   := 0;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF runHours[i] < tempMinHours OR (runHours[i] = tempMinHours AND i < tempMinPumpIdx) THEN
                        tempMinHours   := runHours[i];
                        tempMinPumpIdx := i;
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := tempMinPumpIdx;
        ELSE
            lagPump := 0;
        END_IF;
    ELSIF rotated AND (runHours[prevLeadPump] - minHours > 50) THEN
        leadPump := minPumpIdx;
        IF runningCount >= 2 THEN
            tempMinHours     := LINT#16#7FFFFFFFFFFFFFFF;
            tempMinPumpIdx   := 0;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF runHours[i] < tempMinHours OR (runHours[i] = tempMinHours AND i < tempMinPumpIdx) THEN
                        tempMinHours   := runHours[i];
                        tempMinPumpIdx := i;
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := tempMinPumpIdx;
        ELSE
            lagPump := 0;
        END_IF;
    ELSE
        IF runningCount > prevRunningCount THEN
            needReselect := TRUE;
        ELSE
            needReselect := FALSE;
        END_IF;
        IF leadPump <> prevLeadPump THEN
            tempMinHours     := LINT#16#7FFFFFFFFFFFFFFF;
            tempMinPumpIdx   := 0;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF runHours[i] < tempMinHours OR (runHours[i] = tempMinHours AND i < tempMinPumpIdx) THEN
                        tempMinHours   := runHours[i];
                        tempMinPumpIdx := i;
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := tempMinPumpIdx;
        ELSIF needReselect THEN
            tempMinHours     := LINT#16#7FFFFFFFFFFFFFFF;
            tempMinPumpIdx   := 0;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF runHours[i] < tempMinHours OR (runHours[i] = tempMinHours AND i < tempMinPumpIdx) THEN
                        tempMinHours   := runHours[i];
                        tempMinPumpIdx := i;
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := tempMinPumpIdx;
        ELSE
            lagPump := prevLagPump;
        END_IF;
    END_IF;
END_IF;

IF leadPump <> 0 THEN
    hadValidLeadPump := TRUE;
END_IF;

prevDemand        := demand;
prevRunningCount  := runningCount;
prevLeadPump      := leadPump;
prevLagPump       := lagPump;
END_FUNCTION_BLOCK