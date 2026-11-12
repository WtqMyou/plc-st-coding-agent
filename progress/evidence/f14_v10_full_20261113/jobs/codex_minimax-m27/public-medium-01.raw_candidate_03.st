FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode  : BOOL;
    start : BOOL;
    stop  : BOOL;
END_VAR

VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR

VAR
    lastStart : BOOL := FALSE;
    lastStop  : BOOL := FALSE;
    stopped   : BOOL := FALSE;
    tmp_i     : INT;
    tmp_j     : INT;
    tmp_prio  : INT;
    tmp_sel   : BOOL;
    tmp_run   : BOOL;
END_VAR

// Rising edge detection for stop
IF stop AND NOT lastStop THEN
    stopped := TRUE;
END_IF;

// Rising edge detection for start (only if not stopped)
IF start AND NOT lastStart AND NOT stopped THEN
    IF NOT mode THEN
        // Manual mode: start pumps where selection = TRUE
        FOR tmp_i := 1 TO 5 DO
            IF pumpGroup[tmp_i].selection THEN
                pumpGroup[tmp_i].RunComd := TRUE;
            END_IF;
        END_FOR;
    ELSE
        // Automatic mode: select top 3 by priority
        FOR tmp_i := 1 TO 4 DO
            FOR tmp_j := tmp_i + 1 TO 5 DO
                IF pumpGroup[tmp_j].priority > pumpGroup[tmp_i].priority THEN
                    tmp_prio := pumpGroup[tmp_i].priority;
                    tmp_sel  := pumpGroup[tmp_i].selection;
                    tmp_run  := pumpGroup[tmp_i].RunComd;
                    
                    pumpGroup[tmp_i].priority := pumpGroup[tmp_j].priority;
                    pumpGroup[tmp_i].selection := pumpGroup[tmp_j].selection;
                    pumpGroup[tmp_i].RunComd   := pumpGroup[tmp_j].RunComd;
                    
                    pumpGroup[tmp_j].priority := tmp_prio;
                    pumpGroup[tmp_j].selection := tmp_sel;
                    pumpGroup[tmp_j].RunComd   := tmp_run;
                END_IF;
            END_FOR;
        END_FOR;
        
        // Activate top 3 pumps (indices 1,2,3 after sort)
        FOR tmp_i := 1 TO 3 DO
            pumpGroup[tmp_i].RunComd := TRUE;
        END_FOR;
        FOR tmp_i := 4 TO 5 DO
            pumpGroup[tmp_i].RunComd := FALSE;
        END_FOR;
    END_IF;
END_IF;

// Rising edge detection for stop
IF stopped THEN
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := FALSE;
    END_FOR;
    stopped := FALSE;
END_IF;

lastStart := start;
lastStop  := stop;
END_FUNCTION_BLOCK