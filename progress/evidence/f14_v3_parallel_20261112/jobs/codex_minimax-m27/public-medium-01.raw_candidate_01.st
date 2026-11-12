FUNCTION_BLOCK FB_PumpControl
VAR
    i : INT;
    sortedIndices : ARRAY[1..5] OF INT;
    temp : INT;
    j : INT;
END_VAR

    // Stop button has highest priority
    IF stop THEN
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR;
        RETURN;
    END_IF;

    // Start button applies mode-specific logic
    IF start THEN
        IF NOT mode THEN
            // Manual mode - run pumps where selection is TRUE
            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := pumpGroup[i].selection;
            END_FOR;
        ELSE
            // Automatic mode - select 3 pumps with highest priority
            FOR i := 1 TO 5 DO
                sortedIndices[i] := i;
            END_FOR;

            // Bubble sort by priority (descending)
            FOR i := 1 TO 4 DO
                FOR j := i + 1 TO 5 DO
                    IF pumpGroup[sortedIndices[j]].priority > pumpGroup[sortedIndices[i]].priority THEN
                        temp := sortedIndices[i];
                        sortedIndices[i] := sortedIndices[j];
                        sortedIndices[j] := temp;
                    END_IF;
                END_FOR;
            END_FOR;

            // Deactivate all pumps first
            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := FALSE;
            END_FOR;

            // Activate top 3 pumps by priority
            FOR i := 1 TO 3 DO
                pumpGroup[sortedIndices[i]].RunComd := TRUE;
            END_FOR;
        END_IF;
    END_IF;
END_FUNCTION_BLOCK