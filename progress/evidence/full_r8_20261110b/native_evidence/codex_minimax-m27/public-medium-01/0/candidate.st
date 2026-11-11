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
END_VAR

// Stop has highest priority - all pumps stop
IF stop THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR
// Manual mode
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
// Auto mode - select top 3 by priority, tie-break by smaller index
ELSE
    IF start THEN
        // Bubble sort: higher priority first; equal priority: smaller index first
        FOR i := 1 TO 4 DO
            FOR j := 1 TO 5 - i DO
                IF (pumpGroup[j].priority < pumpGroup[j + 1].priority) OR
                   (pumpGroup[j].priority = pumpGroup[j + 1].priority AND j > j + 1) THEN
                    temp := pumpGroup[j];
                    pumpGroup[j] := pumpGroup[j + 1];
                    pumpGroup[j + 1] := temp;
                END_IF
            END_FOR
        END_FOR
        // Top 3 sorted pumps run
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