(* ENGINEERING_CONTRACT
   count: updated by successful pop then successful push; retained otherwise; initial 0; bounds 0..8; S1,S6.
   full: combinational = (count=8); no latch; S1.
   empty: combinational = (count=0); no latch; S1.
   head: count=0 -> 0; else fifo[1]; combinational after actions; S5.
   fifo valid prefix: compact; shift on successful pop; append on successful push; S4,S7,S8.
   Edge history: local_push_prev/local_pop_prev retained; initial FALSE; updated each scan.
   Priority: pop rising executes before push rising; capacity checked after pop; PUB requirement order.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    pushEn : BOOL;
    pushItem : INT;
    popEn : BOOL;
END_VAR
VAR_OUTPUT
    count : INT;
    full : BOOL;
    empty : BOOL;
    head : INT;
END_VAR
VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR
VAR
    local_push_prev : BOOL := FALSE;
    local_pop_prev : BOOL := FALSE;
    local_count : INT := 0;
    local_rising_push : BOOL;
    local_rising_pop : BOOL;
    i : INT;
END_VAR

(* 计算上升沿，历史在扫描结束时更新 *)
local_rising_push := pushEn AND NOT local_push_prev;
local_rising_pop := popEn AND NOT local_pop_prev;

(* 先执行出队 *)
IF local_rising_pop AND (local_count > 0) THEN
    IF local_count > 1 THEN
        FOR i := 1 TO local_count - 1 DO
            fifo[i] := fifo[i + 1];
        END_FOR;
    END_IF;
    local_count := local_count - 1;
END_IF;

(* 后执行入队 *)
IF local_rising_push AND (local_count < 8) THEN
    local_count := local_count + 1;
    fifo[local_count] := pushItem;
END_IF;

(* 输出 *)
count := local_count;
full := (local_count = 8);
empty := (local_count = 0);
IF local_count = 0 THEN
    head := 0;
ELSE
    head := fifo[1];
END_IF;

(* 更新输入历史 *)
local_push_prev := pushEn;
local_pop_prev := popEn;

END_FUNCTION_BLOCK