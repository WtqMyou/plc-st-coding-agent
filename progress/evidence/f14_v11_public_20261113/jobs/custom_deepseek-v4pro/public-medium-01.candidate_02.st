(* ENGINEERING_CONTRACT
   - Mode FALSE=manual, TRUE=automatic (PUB001).
   - start is rising-edge triggered; stop is level-sensitive with priority (PUB002).
   - Latched local_Running: start edge sets TRUE; stop clears; stop wins (PUB002).
   - When local_Running=FALSE, all RunComd are FALSE (PUB002).
   - Manual and running: each RunComd follows its current selection each scan (PUB001).
   - Automatic and running: select 3 highest priority pumps, larger priority wins;
     ties resolved to lowest array index; remaining two stopped (PUB003).
   - priority and selection are read-only; only RunComd written (PUB004).
   - Unspecified: initial state stopped; priority/selection changes take effect while Running.
*)
(* CONTRACT_RULES [] *)
TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode : BOOL;
    start : BOOL;
    stop : BOOL;
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    local_Running : BOOL;
    local_start_prev : BOOL;
    local_start_rising : BOOL;
    local_selected : ARRAY[1..5] OF BOOL;
    local_bestIdx : INT;
    local_bestPrio : INT;
    local_i : INT;
    local_j : INT;
END_VAR

(* Detect rising edge of start *)
local_start_rising := start AND NOT local_start_prev;

IF stop THEN
    local_Running := FALSE;
ELSIF local_start_rising THEN
    local_Running := TRUE;
END_IF;

(* Update start previous state for next scan *)
local_start_prev := start;

IF NOT local_Running THEN
    FOR local_i := 1 TO 5 DO
        pumpGroup[local_i].RunComd := FALSE;
    END_FOR;
ELSE
    IF NOT mode THEN
        FOR local_i := 1 TO 5 DO
            pumpGroup[local_i].RunComd := pumpGroup[local_i].selection;
        END_FOR;
    ELSE
        FOR local_i := 1 TO 5 DO
            local_selected[local_i] := FALSE;
        END_FOR;

        FOR local_j := 1 TO 3 DO
            local_bestIdx := 0;
            local_bestPrio := -32768;

            FOR local_i := 1 TO 5 DO
                IF NOT local_selected[local_i] THEN
                    IF (local_bestIdx = 0) OR (pumpGroup[local_i].priority > local_bestPrio) THEN
                        local_bestIdx := local_i;
                        local_bestPrio := pumpGroup[local_i].priority;
                    END_IF;
                END_IF;
            END_FOR;

            IF local_bestIdx <> 0 THEN
                local_selected[local_bestIdx] := TRUE;
            END_IF;
        END_FOR;

        FOR local_i := 1 TO 5 DO
            pumpGroup[local_i].RunComd := local_selected[local_i];
        END_FOR;
    END_IF;
END_IF;

END_FUNCTION_BLOCK