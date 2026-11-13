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
    running : BOOL := FALSE;
    tmp_startPrev : BOOL := FALSE;
    tmp_i : INT;
    tmp_j : INT;
    tmp_k : INT;
    tmp_order : ARRAY[1..5] OF INT;
    tmp_isTop : ARRAY[1..5] OF BOOL;
    tmp_prioLeft : INT;
    tmp_prioRight : INT;
END_VAR

(* ENGINEERING_CONTRACT
- Mode select: PUB001/PUB003. mode FALSE=manual, TRUE=auto; outputs follow current mode each scan.
- Running latch: rising edge of start (PUB002) sets running=TRUE; stop=TRUE (PUB004) resets running=FALSE.
- Same-scan priority: stop overrides start; stop and start tests use final same-scan input values.
- Manual RunComd (PUB001/PUB003): RunComd[i] = running AND pumpGroup[i].selection, i=1..5.
- Auto RunComd (PUB001/PUB002): top 3 priorities selected each scan; larger priority wins.
  Ties are unspecified; this block breaks ties by lower array index.
  RunComd[i] = running AND tmp_isTop[i].
- Running state is retained across mode changes until stop; no unstated mode-change reset.
- Units/boundaries: array indices 1..5, priority INT, RunComd BOOL.
*)
(* CONTRACT_RULES [] *)

IF stop THEN
    running := FALSE;
ELSIF (NOT tmp_startPrev) AND start THEN
    running := TRUE;
END_IF;

tmp_startPrev := start;

IF NOT mode THEN
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := running AND pumpGroup[tmp_i].selection;
    END_FOR;
ELSE
    FOR tmp_i := 1 TO 5 DO
        tmp_order[tmp_i] := tmp_i;
        tmp_isTop[tmp_i] := FALSE;
    END_FOR;

    FOR tmp_i := 1 TO 4 DO
        FOR tmp_j := tmp_i + 1 TO 5 DO
            tmp_prioRight := pumpGroup[tmp_order[tmp_j]].priority;
            tmp_prioLeft := pumpGroup[tmp_order[tmp_i]].priority;
            IF tmp_prioRight > tmp_prioLeft THEN
                tmp_k := tmp_order[tmp_i];
                tmp_order[tmp_i] := tmp_order[tmp_j];
                tmp_order[tmp_j] := tmp_k;
            END_IF;
        END_FOR;
    END_FOR;

    FOR tmp_i := 1 TO 3 DO
        tmp_isTop[tmp_order[tmp_i]] := TRUE;
    END_FOR;

    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := running AND tmp_isTop[tmp_i];
    END_FOR;
END_IF;

END_FUNCTION_BLOCK