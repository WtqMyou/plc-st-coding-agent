TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK MultiPumpSwitchingControl
VAR_INPUT
    mode : BOOL;
    start : BOOL;
    stop : BOOL;
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    tmp_runEnable : BOOL;
    tmp_i : INT;
    tmp_j : INT;
    tmp_higher : INT;
    tmp_equal_before : INT;
    tmp_selected : ARRAY[1..5] OF BOOL;
    tmp_startRTrig : R_TRIG;
END_VAR

(* ENGINEERING_CONTRACT
   State tmp_runEnable: activation = rising edge of start while stop=FALSE; hold until stop; reset by stop.
   A start edge occurring while stop=TRUE is consumed and must be re-pressed after stop clears.
   RunComd group: activation = tmp_runEnable AND (manual selection OR auto top-3).
   stop has same-scan priority: clears tmp_runEnable and all RunComd before any start/mode logic.
   Auto selection: exactly 3 pumps; larger priority wins; equal priority tie by lower array index (unspecified).
   Manual selection: pumpGroup[i].selection directly gates RunComd while tmp_runEnable.
   Only RunComd is written; priority and selection are read-only.
*)

(* CONTRACT_RULES [] *)

tmp_startRTrig(CLK := start);

IF stop THEN
    tmp_runEnable := FALSE;
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := FALSE;
    END_FOR;
    RETURN;
END_IF;

IF tmp_startRTrig.Q THEN
    tmp_runEnable := TRUE;
END_IF;

IF mode THEN
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
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := tmp_runEnable AND pumpGroup[tmp_i].selection;
    END_FOR;
END_IF;

END_FUNCTION_BLOCK