TYPE ST_Pump :
STRUCT
    priority   : INT;
    selection  : BOOL;
    RunComd    : BOOL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    mode  : BOOL;
    start : BOOL;
    stop  : BOOL;
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    i         : INT;
    j         : INT;
    sortedIdx : ARRAY[1..5] OF INT;
    temp      : INT;
END_VAR

// sort pumps by priority (descending), stable on equal priority (lower index first)
sortedIdx[1] := 1;
sortedIdx[2] := 2;
sortedIdx[3] := 3;
sortedIdx[4] := 4;
sortedIdx[5] := 5;

FOR i := 1 TO 4 DO
    FOR j := i+1 TO 5 DO
        IF pumpGroup[sortedIdx[j]].priority > pumpGroup[sortedIdx[i]].priority THEN
            temp := sortedIdx[i];
            sortedIdx[i] := sortedIdx[j];
            sortedIdx[j] := temp;
        END_IF
    END_FOR
END_FOR

// stop has highest priority
IF stop THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR
// start enables operation
ELSIF start THEN
    IF mode = FALSE THEN
        // Manual mode: selected pumps run
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := pumpGroup[i].selection;
        END_FOR
    ELSE
        // Automatic mode: top three priority pumps run
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR
        pumpGroup[sortedIdx[1]].RunComd := TRUE;
        pumpGroup[sortedIdx[2]].RunComd := TRUE;
        pumpGroup[sortedIdx[3]].RunComd := TRUE;
    END_IF
ELSE
    // start = FALSE -> no pump runs
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR
END_IF

END_FUNCTION_BLOCK