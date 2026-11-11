FUNCTION_BLOCK FB
VAR_INPUT
    mode : BOOL;
    start : BOOL;
    stop : BOOL;
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    i : INT;
    j : INT;
    higherCount : INT;
END_VAR

IF stop OR NOT start THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR
ELSIF mode THEN
    FOR i := 1 TO 5 DO
        higherCount := 0;
        FOR j := 1 TO 5 DO
            IF (pumpGroup[j].priority > pumpGroup[i].priority) OR
               ((pumpGroup[j].priority = pumpGroup[i].priority) AND (j < i)) THEN
                higherCount := higherCount + 1;
            END_IF
        END_FOR
        IF higherCount < 3 THEN
            pumpGroup[i].RunComd := TRUE;
        ELSE
            pumpGroup[i].RunComd := FALSE;
        END_IF
    END_FOR
ELSE
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := pumpGroup[i].selection;
    END_FOR
END_IF

END_FUNCTION_BLOCK