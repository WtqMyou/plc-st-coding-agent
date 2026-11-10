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
    i : INT;
    j : INT;
    tmp : INT;
    need : INT;
    pickLag : BOOL;
    order : ARRAY[1..5] OF INT;
END_VAR
need := LIMIT(0, demand, 5);
FOR i := 1 TO 5 DO order[i] := i; END_FOR
FOR i := 1 TO 4 DO
    FOR j := i + 1 TO 5 DO
        IF (runHours[order[j]] < runHours[order[i]]) OR
           ((runHours[order[j]] = runHours[order[i]]) AND (order[j] < order[i])) THEN
            tmp := order[i]; order[i] := order[j]; order[j] := tmp;
        END_IF
    END_FOR
END_FOR
runningCount := need;
IF need = 0 THEN
    leadPump := 0; lagPump := 0;
ELSE
    pickLag := FALSE;
    IF leadPump = 0 THEN
        leadPump := order[1]; pickLag := TRUE;
    ELSIF rotated THEN
        IF runHours[leadPump] - runHours[order[1]] > 50 THEN
            leadPump := order[1]; pickLag := TRUE;
        END_IF
    END_IF
    IF need = 1 THEN
        lagPump := 0;
    ELSIF pickLag OR lagPump = 0 THEN
        IF order[1] <> leadPump THEN lagPump := order[1];
        ELSE lagPump := order[2]; END_IF
    END_IF
END_IF
END_FUNCTION_BLOCK
