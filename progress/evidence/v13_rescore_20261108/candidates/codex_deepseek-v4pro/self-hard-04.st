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
    clipped : INT;
    order : ARRAY[1..5] OF INT;
    i : INT;
    j : INT;
    tempIdx : INT;
    bestLead : INT;
    bestLag : INT;
    currentLeadHours : LINT;
    bestLeadHours : LINT;
    memLead : INT := 0;
    memLag : INT := 0;
END_VAR

clipped := demand;
IF clipped < 0 THEN
    clipped := 0;
ELSIF clipped > 5 THEN
    clipped := 5;
END_IF

runningCount := clipped;

IF clipped = 0 THEN
    memLead := 0;
    memLag := 0;
ELSE
    order[1] := 1;
    order[2] := 2;
    order[3] := 3;
    order[4] := 4;
    order[5] := 5;

    FOR i := 1 TO 4 DO
        FOR j := i + 1 TO 5 DO
            IF (runHours[order[j]] < runHours[order[i]]) OR ((runHours[order[j]] = runHours[order[i]]) AND (order[j] < order[i])) THEN
                tempIdx := order[i];
                order[i] := order[j];
                order[j] := tempIdx;
            END_IF
        END_FOR
    END_FOR

    bestLead := order[1];
    IF clipped >= 2 THEN
        bestLag := order[2];
    ELSE
        bestLag := 0;
    END_IF

    IF memLead = 0 THEN
        memLead := bestLead;
        memLag := bestLag;
    ELSE
        IF rotated THEN
            currentLeadHours := runHours[memLead];
            bestLeadHours := runHours[bestLead];
            IF (bestLead <> memLead) AND ((currentLeadHours - bestLeadHours) > 50) THEN
                memLead := bestLead;
                IF clipped >= 2 THEN
                    memLag := bestLag;
                ELSE
                    memLag := 0;
                END_IF
            END_IF
        END_IF

        IF clipped >= 2 THEN
            IF (memLag = 0) OR (memLag = memLead) THEN
                memLag := 0;
                FOR i := 1 TO 5 DO
                    IF (order[i] <> memLead) AND (memLag = 0) THEN
                        memLag := order[i];
                    END_IF
                END_FOR
            END_IF
        ELSE
            memLag := 0;
        END_IF
    END_IF
END_IF

leadPump := memLead;
lagPump := memLag;
END_FUNCTION_BLOCK