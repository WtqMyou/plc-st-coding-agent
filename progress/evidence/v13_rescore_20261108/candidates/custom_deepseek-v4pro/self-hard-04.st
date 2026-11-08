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
    orderedPumps : ARRAY[1..5] OF INT;
    initialized : BOOL := FALSE;
    tmpDemand : INT;
    tmpPump : INT;
    idx1 : INT;
    idx2 : INT;
END_VAR

tmpDemand := demand;
IF tmpDemand < 0 THEN
    tmpDemand := 0;
ELSIF tmpDemand > 5 THEN
    tmpDemand := 5;
END_IF

IF NOT initialized THEN
    FOR idx1 := 1 TO 5 DO
        orderedPumps[idx1] := idx1;
    END_FOR
    FOR idx1 := 1 TO 4 DO
        FOR idx2 := 1 TO 5 - idx1 DO
            IF runHours[orderedPumps[idx2]] > runHours[orderedPumps[idx2 + 1]] THEN
                tmpPump := orderedPumps[idx2];
                orderedPumps[idx2] := orderedPumps[idx2 + 1];
                orderedPumps[idx2 + 1] := tmpPump;
            END_IF
        END_FOR
    END_FOR
    initialized := TRUE;
END_IF

IF rotated THEN
    IF runHours[orderedPumps[2]] < (runHours[orderedPumps[1]] - 50) THEN
        tmpPump := orderedPumps[1];
        orderedPumps[1] := orderedPumps[2];
        orderedPumps[2] := tmpPump;
    END_IF
END_IF

IF tmpDemand = 0 THEN
    leadPump := 0;
    lagPump := 0;
    runningCount := 0;
ELSE
    leadPump := orderedPumps[1];
    runningCount := tmpDemand;
    IF tmpDemand >= 2 THEN
        lagPump := orderedPumps[2];
    ELSE
        lagPump := 0;
    END_IF
END_IF

END_FUNCTION_BLOCK