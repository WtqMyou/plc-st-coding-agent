TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE

(* CONTRACT_RULES [] *)

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
    RunEnabled : BOOL;
    tmp_i : INT;
    tmp_slot : INT;
    tmp_best : INT;
    tmp_best_priority : INT;
    tmp_found : BOOL;
    tmp_selected : ARRAY[1..5] OF BOOL;
END_VAR

(*
ENGINEERING_CONTRACT
RunComd[1..5]: active while RunEnabled and current operating-set membership is true; retained per scan only while that condition stays true; stop clears all commands; changing selection/top-3 set clears only no-longer-selected pumps; same-scan priority stop > start.
RunEnabled: activated by start; held until stop; explicit deactivation is stop only; stop has priority when start and stop are simultaneously asserted.
mode: FALSE = manual, command set is pumpGroup[i].selection; TRUE = automatic, command set is the 3 highest-priority pumps. Ties use lower array index 1..5.
Boundaries: fixed array 1..5; only RunComd is written.
PUB: PUB001-PUB004.
*)

IF stop THEN
    RunEnabled := FALSE;
ELSIF start THEN
    RunEnabled := TRUE;
END_IF;

IF mode THEN
    FOR tmp_i := 1 TO 5 DO
        tmp_selected[tmp_i] := FALSE;
    END_FOR;

    FOR tmp_slot := 1 TO 3 DO
        tmp_best := 0;
        tmp_best_priority := 0;
        tmp_found := FALSE;

        FOR tmp_i := 1 TO 5 DO
            IF NOT tmp_selected[tmp_i] THEN
                IF (NOT tmp_found) OR (pumpGroup[tmp_i].priority > tmp_best_priority) THEN
                    tmp_best := tmp_i;
                    tmp_best_priority := pumpGroup[tmp_i].priority;
                    tmp_found := TRUE;
                END_IF;
            END_IF;
        END_FOR;

        IF tmp_found THEN
            tmp_selected[tmp_best] := TRUE;
        END_IF;
    END_FOR;

    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := tmp_selected[tmp_i] AND RunEnabled;
    END_FOR;
ELSE
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := pumpGroup[tmp_i].selection AND RunEnabled;
    END_FOR;
END_IF;

END_FUNCTION_BLOCK