FUNCTION_BLOCK FB
VAR_INPUT
    demand : INT;
    runHours : ARRAY[1..5] OF LINT;
    rotated : BOOL;
END_VAR
VAR_OUTPUT
    leadPump : INT;
    lagPump : INT;
    runningCount : INT;
END_VAR
VAR
    prevLeadPump : INT := 0;
    prevLagPump : INT := 0;
    prevRunningCount : INT := 0;
    currentDemandClipped : INT;
    prevLeadValid : BOOL;
    shortestPump : INT;
    shortestHours : LINT;
    leadChanged : BOOL;
    runningRise : BOOL;
    newLag : INT;
    i : INT;
END_VAR

IF demand < 0 THEN
    currentDemandClipped := 0;
ELSIF demand > 5 THEN
    currentDemandClipped := 5;
ELSE
    currentDemandClipped := demand;
END_IF;
runningCount := currentDemandClipped;

leadPump := prevLeadPump;
lagPump := prevLagPump;

IF currentDemandClipped = 0 THEN
    leadPump := 0;
    lagPump := 0;
    prevLeadPump := leadPump;
    prevLagPump := lagPump;
    prevRunningCount := runningCount;
    RETURN;
END_IF;

IF prevLeadPump >= 1 AND prevLeadPump <= 5 THEN
    prevLeadValid := TRUE;
ELSE
    prevLeadValid := FALSE;
END_IF;

shortestPump := 1;
shortestHours := runHours[1];
FOR i := 2 TO 5 DO
    IF runHours[i] < shortestHours THEN
        shortestHours := runHours[i];
        shortestPump := i;
    ELSIF runHours[i] = shortestHours AND i < shortestPump THEN
        shortestPump := i;
    END_IF;
END_FOR;

IF NOT prevLeadValid THEN
    leadPump := shortestPump;
ELSE
    IF rotated THEN
        IF runHours[prevLeadPump] - shortestHours > 50 THEN
            leadPump := shortestPump;
        ELSE
            leadPump := prevLeadPump;
        END_IF;
    ELSE
        leadPump := prevLeadPump;
    END_IF;
END_IF;

IF currentDemandClipped >= 2 THEN
    leadChanged := (leadPump <> prevLeadPump);
    runningRise := (runningCount > prevRunningCount);
    IF leadChanged OR runningRise THEN
        newLag := 0;
        FOR i := 1 TO 5 DO
            IF i <> leadPump THEN
                IF newLag = 0 THEN
                    newLag := i;
                ELSE
                    IF runHours[i] < runHours[newLag] THEN
                        newLag := i;
                    ELSIF runHours[i] = runHours[newLag] AND i < newLag THEN
                        newLag := i;
                    END_IF;
                END_IF;
            END_IF;
        END_FOR;
        lagPump := newLag;
    ELSE
        lagPump := prevLagPump;
    END_IF;
ELSE
    lagPump := 0;
END_IF;

prevLeadPump := leadPump;
prevLagPump := lagPump;
prevRunningCount := runningCount;

END_FUNCTION_BLOCK