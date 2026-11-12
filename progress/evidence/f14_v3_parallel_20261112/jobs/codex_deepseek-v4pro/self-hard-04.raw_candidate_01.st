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
    demandClipped : INT;
    prevLeadPump : INT := 0;
    prevLagPump : INT := 0;
    prevRunningCount : INT := 0;
    minPump : INT;
    minHours : LINT;
    bestLagPump : INT;
    bestLagHours : LINT;
    idx : INT;
    leadChanged : BOOL;
    countRose : BOOL;
    rotationThreshold : LINT := 50;
END_VAR

demandClipped := demand;
IF demandClipped < 0 THEN
    demandClipped := 0;
ELSIF demandClipped > 5 THEN
    demandClipped := 5;
END_IF;

runningCount := demandClipped;

IF demandClipped <= 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSE
    minPump := 1;
    minHours := runHours[1];
    FOR idx := 2 TO 5 BY 1 DO
        IF runHours[idx] < minHours THEN
            minPump := idx;
            minHours := runHours[idx];
        END_IF;
    END_FOR;

    IF prevLeadPump = 0 THEN
        leadPump := minPump;
    ELSIF rotated THEN
        IF runHours[prevLeadPump] - minHours > rotationThreshold THEN
            leadPump := minPump;
        ELSE
            leadPump := prevLeadPump;
        END_IF;
    ELSE
        leadPump := prevLeadPump;
    END_IF;

    IF demandClipped < 2 THEN
        lagPump := 0;
    ELSE
        leadChanged := leadPump <> prevLeadPump;
        countRose := demandClipped > prevRunningCount;

        IF leadChanged OR countRose THEN
            bestLagPump := 0;
            FOR idx := 1 TO 5 BY 1 DO
                IF idx <> leadPump THEN
                    IF bestLagPump = 0 THEN
                        bestLagPump := idx;
                        bestLagHours := runHours[idx];
                    ELSIF runHours[idx] < bestLagHours THEN
                        bestLagPump := idx;
                        bestLagHours := runHours[idx];
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := bestLagPump;
        ELSE
            lagPump := prevLagPump;
        END_IF;
    END_IF;
END_IF;

prevLeadPump := leadPump;
prevLagPump := lagPump;
prevRunningCount := runningCount;

END_FUNCTION_BLOCK