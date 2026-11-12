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
    tmp_startR : R_TRIG;
END_VAR

(* ENGINEERING_CONTRACT
   Mode/selection: mode=FALSE => manual set = pumpGroup[i].selection;
                   mode=TRUE  => auto set = top-3 priority values, tie lower index (PUB001, PUB003).
   Run command activation: rising edge of start when stop=FALSE latches tmp_runEnable=TRUE.
                           Start held after stop does not restart until a new rising edge.
   Retention/latch: tmp_runEnable holds after start until stop; each pump RunComd follows
                    current mode/selection and tmp_runEnable every scan (PUB002).
   Stop/reset: stop=TRUE clears tmp_runEnable and all RunComd, same-scan priority
               over start and mode computation (PUB004).
   Boundaries: priority INT, exactly 3 pumps selected in auto, tie lower index
               unspecified interpretation; only RunComd is written.
*)

(* CONTRACT_RULES [] *)

tmp_startR(CLK := start);

IF stop THEN
    tmp_runEnable := FALSE;
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := FALSE;
    END_FOR;
    RETURN;
END_IF;

IF tmp_startR.Q THEN
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