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
    clippedDemand : INT;
    prevClippedDemand : INT;
    prevLead : INT;
    prevLag : INT;
    minPump : INT;
    newLead : INT;
    minHours : LINT;
    lagCandidateHours : LINT;
    lagFound : BOOL;
    index : INT;
END_VAR

IF demand < 0 THEN
    clippedDemand := 0;
ELSIF demand > 5 THEN
    clippedDemand := 5;
ELSE
    clippedDemand := demand;
END_IF

runningCount := clippedDemand;

IF clippedDemand <= 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSE
    minPump := 1;
    minHours := runHours[1];

    FOR index := 2 TO 5 DO
        IF runHours[index] < minHours THEN
            minHours := runHours[index];
            minPump := index;
        END_IF
    END_FOR

    IF prevLead = 0 THEN
        newLead := minPump;
    ELSIF rotated AND ((runHours[prevLead] - minHours) > LINT#50) THEN
        newLead := minPump;
    ELSE
        newLead := prevLead;
    END_IF

    leadPump := newLead;

    IF clippedDemand >= 2 THEN
        IF (newLead <> prevLead) OR (clippedDemand > prevClippedDemand) THEN
            lagFound := FALSE;

            FOR index := 1 TO 5 DO
                IF index <> newLead THEN
                    IF NOT lagFound THEN
                        lagPump := index;
                        lagCandidateHours := runHours[index];
                        lagFound := TRUE;
                    ELSIF runHours[index] < lagCandidateHours THEN
                        lagPump := index;
                        lagCandidateHours := runHours[index];
                    END_IF
                END_IF
            END_FOR
        ELSE
            lagPump := prevLag;
        END_IF
    ELSE
        lagPump := 0;
    END_IF
END_IF

prevClippedDemand := clippedDemand;
prevLead := leadPump;
prevLag := lagPump;
END_FUNCTION_BLOCK