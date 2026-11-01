FUNCTION_BLOCK FB
VAR_INPUT
    demand : INT;
    runHours : ARRAY[1..5] OF LINT;
    rotated : BOOL;
END_VAR
VAR_OUTPUT
    leadPump : INT;
    lagPump : INT;
    runningCount : INT;
END_VAR
VAR
    i : INT;
    j : INT;
    need : INT;
    tmp : LINT;
    order : ARRAY[1..5] OF INT;
END_VAR

(* 需求先裁剪到 0..5，否则后面按 order[i] 取泵号会越界 *)
need := demand;
IF need < 0 THEN
    need := 0;
ELSIF need > 5 THEN
    need := 5;
END_IF

(* 选择排序：按运行小时升序得到泵号次序 *)
FOR i := 1 TO 5 DO
    order[i] := i;
END_FOR
FOR i := 1 TO 4 DO
    FOR j := i + 1 TO 5 DO
        IF runHours[order[j]] < runHours[order[i]] THEN
            tmp := order[i];
            order[i] := order[j];
            order[j] := tmp;
        END_IF
    END_FOR
END_FOR

runningCount := need;
IF need = 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSIF need = 1 THEN
    leadPump := order[1];
    lagPump := 0;
ELSE
    leadPump := order[1];
    lagPump := order[2];
    (* 均衡轮换：两台泵小时数差小于阈值 50 时互换主备，
       让备泵有机会顶上去，避免主泵长期独挑磨损。 *)
    IF rotated AND (runHours[order[2]] - runHours[order[1]]) < 50 THEN
        leadPump := order[2];
        lagPump := order[1];
    END_IF
END_IF
END_FUNCTION_BLOCK
