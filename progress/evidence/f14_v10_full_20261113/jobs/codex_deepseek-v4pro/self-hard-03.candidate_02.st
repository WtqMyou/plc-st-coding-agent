(*
ENGINEERING_CONTRACT
Contract basis: PUB001-PUB007 (operation order, outputs, compact buffer); edges per PUB003.
State/output   Activation                            Retention     Reset  Same-scan priority        Bounds
local history  store pushEn/popEn each scan          VAR static    none   edge=signal AND NOT hist  BOOL
count          pop edge accepted first if count>0;    VAR output    none   pop acts before push      INT 0..8
               push edge accepted then if count<8
full/empty     derived from final count               derived       none   after both edge actions   BOOL, count=8/count=0
head           count=0 -> 0 else fifo[1]              derived       none   after final compaction    INT
fifo           pop shifts valid item i+1 to i;        IN_OUT buffer none   shift before push append  valid prefix ordered
               accepted push writes fifo[new count]
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    pushEn : BOOL;
    pushItem : INT;
    popEn : BOOL;
END_VAR
VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR
VAR_OUTPUT
    count : INT;
    full : BOOL;
    empty : BOOL;
    head : INT;
END_VAR
VAR
    local_push_history : BOOL;
    local_pop_history : BOOL;
    local_push_rise : BOOL;
    local_pop_rise : BOOL;
    tmp_i : INT;
END_VAR

local_push_rise := pushEn AND NOT local_push_history;
local_pop_rise := popEn AND NOT local_pop_history;

IF local_pop_rise AND (count > 0) THEN
    IF count > 1 THEN
        FOR tmp_i := 1 TO count - 1 BY 1 DO
            fifo[tmp_i] := fifo[tmp_i + 1];
        END_FOR;
    END_IF;
    count := count - 1;
END_IF;

IF local_push_rise THEN
    IF count < 8 THEN
        count := count + 1;
        fifo[count] := pushItem;
    END_IF;
END_IF;

full := (count = 8);
empty := (count = 0);

IF count = 0 THEN
    head := 0;
ELSE
    head := fifo[1];
END_IF;

local_push_history := pushEn;
local_pop_history := popEn;
END_FUNCTION_BLOCK