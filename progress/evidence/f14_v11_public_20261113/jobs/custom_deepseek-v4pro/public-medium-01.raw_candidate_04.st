(* ENGINEERING_CONTRACT
   - Mode FALSE=manual, TRUE=automatic (PUB001).
   - Start is edge-triggered: a new FALSE->TRUE start pulse is required after stop release
     before pumps may run again; stop has priority over a level-held start (PUB001/PUB002).
   - local_Running is retained run state: set by rising edge of start while stop=FALSE,
     cleared immediately by stop=TRUE (PUB002).
   - When local_Running=FALSE, all RunComd are FALSE (PUB002).
   - Manual running: each RunComd follows its current selection each scan (PUB001).
   - Automatic running: select 3 highest priority pumps, tie lower index; remaining stopped (PUB003).
   - priority/selection read-only; only RunComd written (PUB004).
*)
(* CONTRACT_RULES [] *)
TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE

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
    local_selected : ARRAY[1..5] OF BOOL;
    local_bestIdx : INT;
    local_bestPrio : INT;
    local_i : INT;
    local_j : INT;
    local_rtStart : R_TRIG;
END_VAR

local_rtStart(CLK := start);

IF stop THEN
    local_Running := FALSE;
ELSE
    local_Running := local_Running OR local_rtStart.Q;
END_IF;

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