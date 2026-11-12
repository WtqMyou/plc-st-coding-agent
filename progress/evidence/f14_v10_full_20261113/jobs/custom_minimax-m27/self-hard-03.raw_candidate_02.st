FUNCTION_BLOCK FB
VAR_INPUT
    pushEn  : BOOL;
    pushItem: INT;
    popEn   : BOOL;
END_VAR
VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR
VAR_OUTPUT
    count : INT := 0;
    full  : BOOL;
    empty : BOOL;
    head  : INT;
END_VAR
VAR
    pushTrig  : R_TRIG;
    popTrig   : R_TRIG;
    prevCount : INT;
    tmp_end   : INT;
    tmp_i     : INT;
END_VAR

(*
ENGINEERING_CONTRACT
================================================================================
| Output/State  | Activation          | Retention  | Reset      | Priority   |
|---------------|---------------------|------------|------------|------------|
| count         | Rising pushEn OK    | Hold       | Implicit 0 | After pop  |
| full          | count = 8           | Hold       | Implicit   | Same-scan  |
| empty         | count = 0           | Hold       | Implicit   | Same-scan  |
| head          | empty→0 else fifo[1]| Hold       | Implicit   | Same-scan  |
| fifo compact  | After pop+push seq  | Hold       | Implicit   | Pop first  |
--------------------------------------------------------------------------------
PUB001: pushEn rising edge triggers one push per low-to-high transition.
PUB002: popEn rising edge triggers one pop per low-to-high transition.
PUB003: popEn rising edge executes first; removes first item if non-empty.
PUB004: pushEn rising edge executes after pop; appends if count < 8.
PUB005: Full queue with both edges: pop frees slot then push appends.
PUB006: Empty queue with both edges: pop no-op, push adds single item.
PUB007: count = 0..8; full iff count = 8; empty iff count = 0.
PUB008: head = 0 when empty; else head = first item.
PUB009: fifo[1..count] is compact logical queue ordered by pop sequence.
PUB010: fifo[1] = head when non-empty; unspecified beyond count.
--------------------------------------------------------------------------------
CONTRACT_RULES: []
================================================================================
*)
prevCount := count;

pushTrig(CLK := pushEn);
popTrig(CLK := popEn);

IF popTrig.Q AND prevCount > 0 THEN
    tmp_end := prevCount - 1;
    FOR tmp_i := 1 TO tmp_end DO
        fifo[tmp_i] := fifo[tmp_i + 1];
    END_FOR;
    count := prevCount - 1;
ELSE
    count := prevCount;
END_IF;

IF pushTrig.Q THEN
    IF (popTrig.Q AND prevCount > 0) OR (NOT popTrig.Q AND count < 8) THEN
        fifo[count + 1] := pushItem;
        count := count + 1;
    END_IF;
END_IF;

full  := (count = 8);
empty := (count = 0);
head  := 0;
IF NOT empty THEN
    head := fifo[1];
END_IF;

END_FUNCTION_BLOCK