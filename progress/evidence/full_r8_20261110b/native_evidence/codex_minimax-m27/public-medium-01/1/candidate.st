TYPE ST_Pump : STRUCT
    priority  : INT;
    selection : BOOL;
    RunComd   : BOOL;
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
    temp      : ST_Pump;
    sortedIdx : ARRAY[1..5] OF INT;
END_VAR

// Stop has highest priority - all pumps stop immediately
IF stop THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR
// Manual mode: each pump follows its own selection when start is pressed
ELSIF NOT mode THEN
    IF start THEN
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := pumpGroup[i].selection;
        END_FOR
    ELSE
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR
    END_IF
// Auto mode: run top 3 by priority, tie-break by smaller index
ELSE
    IF start THEN
        // Initialize sorted index array
        FOR i := 1 TO 5 DO
            sortedIdx[i] := i;
        END_FOR
        // Bubble sort indices by priority (descending), tie-break by index (ascending)
        FOR i := 1 TO 4 DO
            FOR j := 1 TO 5 - i DO
                IF (pumpGroup[sortedIdx[j]].priority < pumpGroup[sortedIdx[j + 1]].priority) OR
                   (pumpGroup[sortedIdx[j]].priority = pumpGroup[sortedIdx[j + 1]].priority AND sortedIdx[j] > sortedIdx[j + 1]) THEN
                    temp := pumpGroup[sortedIdx[j]];
                    pumpGroup[sortedIdx[j]] := pumpGroup[sortedIdx[j + 1]];
                    pumpGroup[sortedIdx[j + 1]] := temp;
                    // Swap indices
                    i := sortedIdx[j];
                    sortedIdx[j] := sortedIdx[j + 1];
                    sortedIdx[j + 1] := i;
                END_IF
            END_FOR
        END_FOR
        // Assign RunComd based on sorted order: top 3 run, bottom 2 standby
        FOR i := 1 TO 5 DO
            IF i <= 3 THEN
                pumpGroup[i].RunComd := TRUE;
            ELSE
                pumpGroup[i].RunComd := FALSE;
            END_IF
        END_FOR
    ELSE
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR
    END_IF
END_IF
END_FUNCTION_BLOCK