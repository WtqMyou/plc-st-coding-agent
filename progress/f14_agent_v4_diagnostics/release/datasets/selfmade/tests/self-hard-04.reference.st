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
    need : INT;
    prevNeed : INT;
    best : INT;
    lagMin : INT;
    leadWas : INT;
END_VAR

(* 需求先裁剪到 0..5，否则按泵号取工时可能越界 *)
need := demand;
IF need < 0 THEN
    need := 0;
ELSIF need > 5 THEN
    need := 5;
END_IF
runningCount := need;

(* 全场（工时, 泵号）升序里的第一名：先比工时，工时相同取小泵号 *)
best := 1;
FOR i := 2 TO 5 DO
    IF (runHours[i] < runHours[best]) OR
       ((runHours[i] = runHours[best]) AND (i < best)) THEN
        best := i;
    END_IF
END_FOR

IF need = 0 THEN
    (* 需求归零：主备都清掉，下次正需求重新初选 *)
    leadPump := 0;
    lagPump := 0;
ELSIF leadPump = 0 THEN
    (* 初选：全场最短工时的泵作主泵 *)
    leadPump := best;
ELSE
    (* 迟滞：只有请求有效、且当前主泵比最短工时泵**严格多 50 h 以上**才换主。
       这里刻意不写成"每拍无条件选最短工时"——那样会把迟滞阈值架空，
       每次请求都会立刻换泵，反而加剧磨损与工艺扰动。 *)
    IF rotated AND ((runHours[leadPump] - runHours[best]) > 50) THEN
        leadPump := best;
    END_IF
END_IF

IF need <= 1 THEN
    (* 需求 0/1 台时没有备泵 *)
    lagPump := 0;
ELSE
    (* 备泵：除主泵外的其余泵里（工时, 泵号）最小者 *)
    lagMin := 0;
    FOR i := 1 TO 5 DO
        IF i <> leadPump THEN
            IF lagMin = 0 THEN
                lagMin := i;
            ELSIF (runHours[i] < runHours[lagMin]) OR
                  ((runHours[i] = runHours[lagMin]) AND (i < lagMin)) THEN
                lagMin := i;
            END_IF
        END_IF
    END_FOR
    (* 只在初选、升至需要备泵、或换主时重选备泵，其余拍保留原备泵 *)
    IF (lagPump = 0) OR (lagPump = leadPump) OR (need > prevNeed) OR
       (leadPump <> leadWas) THEN
        lagPump := lagMin;
    END_IF
END_IF

prevNeed := need;
leadWas := leadPump;
END_FUNCTION_BLOCK
