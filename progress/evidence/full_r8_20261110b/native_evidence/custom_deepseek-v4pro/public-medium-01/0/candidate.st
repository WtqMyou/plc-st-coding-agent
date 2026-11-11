TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE

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
    idx : ARRAY[1..5] OF INT;
    i : INT;
    j : INT;
    temp : INT;
    bestPos : INT;
END_VAR

IF stop OR NOT start THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR
ELSIF NOT mode THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := pumpGroup[i].selection;
    END_FOR
ELSE
    FOR i := 1 TO 5 DO
        idx[i] := i;
    END_FOR

    FOR i := 1 TO 4 DO
        bestPos := i;
        FOR j := i + 1 TO 5 DO
            IF (pumpGroup[idx[j]].priority > pumpGroup[idx[bestPos]].priority) OR
               ((pumpGroup[idx[j]].priority = pumpGroup[idx[bestPos]].priority) AND (idx[j] < idx[bestPos])) THEN
                bestPos := j;
            END_IF
        END_FOR
        IF bestPos <> i THEN
            temp := idx[i];
            idx[i] := idx[bestPos];
            idx[bestPos] := temp;
        END_IF
    END_FOR

    FOR i := 1 TO 3 DO
        pumpGroup[idx[i]].RunComd := TRUE;
    END_FOR
    FOR i := 4 TO 5 DO
        pumpGroup[idx[i]].RunComd := FALSE;
    END_FOR
END_IF

END_FUNCTION_BLOCK