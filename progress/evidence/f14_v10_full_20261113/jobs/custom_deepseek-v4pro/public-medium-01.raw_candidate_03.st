TYPE ST_Pump :
STRUCT
    priority : INT;      (* Larger value = higher priority. Read-only to FB. *)
    selection : BOOL;    (* Manual-selection state. Read-only to FB. *)
    RunComd : BOOL;      (* Written by FB. TRUE = run, FALSE = stop. *)
END_STRUCT
END_TYPE

FUNCTION_BLOCK MultiPumpSwitchingControl
VAR_INPUT
    mode  : BOOL;  (* FALSE = Manual, TRUE = Automatic *)
    start : BOOL;  (* Start button - rising-edge triggered *)
    stop  : BOOL;  (* Stop button - level sensitive, overrides start *)
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump; (* Read priority/selection, write RunComd only *)
END_VAR
VAR
    tmp_runEnable      : BOOL;                    (* Latched run command state *)
    tmp_start_ris      : R_TRIG;                  (* Rising-edge detector for start *)
    tmp_i              : INT;
    tmp_j              : INT;
    tmp_higher         : INT;                     (* Number of pumps with strictly higher priority *)
    tmp_equal_before   : INT;                     (* Equal priority pumps with lower array index *)
    tmp_selected       : ARRAY[1..5] OF BOOL;     (* Automatic top-3 selection set *)
END_VAR

(* ENGINEERING_CONTRACT
   mode: FALSE=manual set = pumpGroup[i].selection; TRUE=auto set = top-3 priority values,
         ties resolved toward lower array index. Larger priority = higher priority.
   start: rising-edge latch, holds tmp_runEnable TRUE until stop.
   stop: level-sensitive, immediate priority over start and mode; clears latch and all RunComd.
   outputs: RunComd = tmp_runEnable AND selected/auto-selected for each pump.
   same-scan: stop wins over start; mode change immediately recomputes active set.
   boundaries: priority INT, exactly 3 pumps selected in auto, tie lower index.
*)

(* CONTRACT_RULES [] *)

(* Update start-edge memory every scan, even when stop is active,
   so a held start cannot false-trigger after stop is released. *)
tmp_start_ris(CLK := start);

IF stop THEN
    tmp_runEnable := FALSE;
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := FALSE;
    END_FOR;
    RETURN;
END_IF;

IF tmp_start_ris.Q THEN
    tmp_runEnable := TRUE;
END_IF;

IF mode THEN
    (* Automatic mode: select exactly 3 pumps with highest priority,
       lower array index used for ties. *)
    FOR tmp_i := 1 TO 5 DO
        tmp_higher := 0;
        tmp_equal_before := 0;
        FOR tmp_j := 1 TO 5 DO
            IF pumpGroup[tmp_j].priority > pumpGroup[tmp_i].priority THEN
                tmp_higher := tmp_higher + 1;
            ELSIF (tmp_j < tmp_i) AND (pumpGroup[tmp_j].priority = pumpGroup[tmp_i].priority) THEN
                tmp_equal_before := tmp_equal_before + 1;
            END_IF;
        END_FOR;
        tmp_selected[tmp_i] := ((tmp_higher + tmp_equal_before) < 3);
    END_FOR;

    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := tmp_runEnable AND tmp_selected[tmp_i];
    END_FOR;
ELSE
    (* Manual mode: use each pump's manual selection. *)
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := tmp_runEnable AND pumpGroup[tmp_i].selection;
    END_FOR;
END_IF;

END_FUNCTION_BLOCK