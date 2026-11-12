TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_PumpControl
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
    sortedIndices : ARRAY[1..5] OF INT;
    temp : INT;
    j : INT;
END_VAR

    IF stop THEN
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR;
        RETURN;
    END_IF;

    IF start THEN
        IF NOT mode THEN
            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := pumpGroup[i].selection;
            END_FOR;
        ELSE
            FOR i := 1 TO 5 DO
                sortedIndices[i] := i;
            END_FOR;

            FOR i := 1 TO 4 DO
                FOR j := i + 1 TO 5 DO
                    IF pumpGroup[sortedIndices[j]].priority > pumpGroup[sortedIndices[i]].priority THEN
                        temp := sortedIndices[i];
                        sortedIndices[i] := sortedIndices[j];
                        sortedIndices[j] := temp;
                    END_IF;
                END_FOR;
            END_FOR;

            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := FALSE;
            END_FOR;

            FOR i := 1 TO 3 DO
                pumpGroup[sortedIndices[i]].RunComd := TRUE;
            END_FOR;
        END_IF;
    END_IF;
END_FUNCTION_BLOCK