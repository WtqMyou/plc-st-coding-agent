TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_MultiPumpSwitchingControl
(* ENGINEERING_CONTRACT
   - mode=FALSE: manual mode; RunComd follows selection (PUB001/PUB002).
   - mode=TRUE: automatic mode; select three pumps with highest priority (PUB001/PUB003).
   - start: activates run enable; stop: deactivates run enable and stops all pumps (PUB002/PUB004).
   - Same-scan stop priority: if stop=TRUE, stop wins over start.
   - Run command is evaluated as selected AND run enable each scan.
   - Larger priority wins. Equal priority is unspecified; lower array index wins.
   - Mode transition with run enable retained is unspecified; retained run enable is used.
*)
(* CONTRACT_RULES [] *)
VAR
    runEnable : BOOL := FALSE;
    tmp_rank : INT;
    tmp_selected : ARRAY[1..5] OF BOOL;
    i : INT;
    j : INT;
END_VAR

IF stop THEN
    runEnable := FALSE;
ELSIF start THEN
    runEnable := TRUE;
END_IF;

IF mode THEN
    FOR i := 1 TO 5 DO
        tmp_rank := 0;
        FOR j := 1 TO 5 DO
            IF (pumpGroup[j].priority > pumpGroup[i].priority)
               OR ((pumpGroup[j].priority = pumpGroup[i].priority) AND (j < i)) THEN
                tmp_rank := tmp_rank + 1;
            END_IF;
        END_FOR;

        IF tmp_rank < 3 THEN
            tmp_selected[i] := TRUE;
        ELSE
            tmp_selected[i] := FALSE;
        END_IF;
    END_FOR;
ELSE
    FOR i := 1 TO 5 DO
        tmp_selected[i] := pumpGroup[i].selection;
    END_FOR;
END_IF;

FOR i := 1 TO 5 DO
    pumpGroup[i].RunComd := tmp_selected[i] AND runEnable;
END_FOR;

END_FUNCTION_BLOCK