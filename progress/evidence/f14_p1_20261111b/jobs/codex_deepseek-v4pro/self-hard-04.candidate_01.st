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
    previousLeadPump : INT := 0;
    previousLagPump : INT := 0;
    previousRunningCount : INT := 0;
    clippedDemand : INT;
    minimumPump : INT;
    minimumHours : LINT;
    lagCandidate : INT;
    pumpIndex : INT;
END_VAR

clippedDemand := demand;
IF clippedDemand < 0 THEN
    clippedDemand := 0;
ELSIF clippedDemand > 5 THEN
    clippedDemand := 5;
END_IF;

runningCount := clippedDemand;

IF clippedDemand <= 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSE
    minimumHours := runHours[1];
    minimumPump := 1;
    FOR pumpIndex := 2 TO 5 DO
        IF (runHours[pumpIndex] < minimumHours) OR
           ((runHours[pumpIndex] = minimumHours) AND (pumpIndex < minimumPump)) THEN
            minimumHours := runHours[pumpIndex];
            minimumPump := pumpIndex;
        END_IF;
    END_FOR;

    IF (previousLeadPump < 1) OR (previousLeadPump > 5) THEN
        leadPump := minimumPump;
    ELSIF rotated AND
          (previousLeadPump >= 1) AND
          (previousLeadPump <= 5) AND
          (runHours[previousLeadPump] - minimumHours > 50) THEN
        leadPump := minimumPump;
    ELSE
        leadPump := previousLeadPump;
    END_IF;

    IF clippedDemand >= 2 THEN
        IF (leadPump <> previousLeadPump) OR (runningCount > previousRunningCount) THEN
            lagCandidate := 0;
            FOR pumpIndex := 1 TO 5 DO
                IF pumpIndex <> leadPump THEN
                    IF lagCandidate = 0 THEN
                        lagCandidate := pumpIndex;
                    ELSIF (runHours[pumpIndex] < runHours[lagCandidate]) OR
                          ((runHours[pumpIndex] = runHours[lagCandidate]) AND
                           (pumpIndex < lagCandidate)) THEN
                        lagCandidate := pumpIndex;
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := lagCandidate;
        ELSE
            lagPump := previousLagPump;
        END_IF;
    ELSE
        lagPump := 0;
    END_IF;
END_IF;

previousLeadPump := leadPump;
previousLagPump := lagPump;
previousRunningCount := runningCount;
END_FUNCTION_BLOCK