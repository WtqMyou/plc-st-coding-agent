(* ENGINEERING_CONTRACT
===================
| Output/State        | Activation               | Retention | Explicit Reset | Same-Scan Priority | Units/Range |
|---------------------|--------------------------|-----------|----------------|--------------------|-------------|
| pumpGroup[].RunComd | start rising edge        | HOLD      | stop edge      | stop > start       | BOOL[1..5]  |
| Manual: selected    | selection=TRUE ∧ start   | HOLD      | stop edge      | stop > start       | pumpGroup   |
| Auto: top-3 priority| top-3 priority ∧ start   | HOLD      | stop edge      | stop > start       | sorted[1..3]|
| Mode switch         | immediate re-eval        | N/A       | N/A            | N/A                | mode BOOL   |

PUB001 (91-265): Mode determines Manual vs Auto selection logic
PUB002 (266-350): Manual mode uses pumpGroup[].selection as qualifier
PUB003 (351-463): Auto mode selects 3 highest-priority pumps
PUB004 (464-652): Stop button deactivates all pumps
*)
(* CONTRACT_RULES [] *)

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
    startRising : BOOL := FALSE;
    stopRising  : BOOL := FALSE;
    tmp_i     : INT;
    tmp_j     : INT;
    tmp_prio  : INT;
    tmp_sel   : BOOL;
    tmp_run   : BOOL;
END_VAR

// Rising edge detection for start
startRising := start AND NOT lastStart;

// Rising edge detection for stop
stopRising := stop AND NOT lastStop;

// Rising edge: stop takes priority, stops all pumps immediately
IF stopRising THEN
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := FALSE;
    END_FOR;
END_IF;

// Rising edge: start activates pumps (only if stop not asserted this scan)
IF startRising AND NOT stopRising THEN
    IF NOT mode THEN
        // Manual mode: start pumps where selection = TRUE
        FOR tmp_i := 1 TO 5 DO
            IF pumpGroup[tmp_i].selection THEN
                pumpGroup[tmp_i].RunComd := TRUE;
            END_IF;
        END_FOR;
    ELSE
        // Automatic mode: select top 3 by priority (bubble sort descending)
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
        // Deactivate remaining pumps
        FOR tmp_i := 4 TO 5 DO
            pumpGroup[tmp_i].RunComd := FALSE;
        END_FOR;
    END_IF;
END_IF;

lastStart := start;
lastStop  := stop;
END_FUNCTION_BLOCK