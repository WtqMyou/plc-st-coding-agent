(* ENGINEERING_CONTRACT
   Activation: pushEn/popEn rising edges vs stored previous inputs; no repeat while held (PUB001-PUB039).
   Same-scan priority: pop edge is processed first, then push edge; simultaneous full pair frees a slot then appends; simultaneous empty pair adds only new item (PUB001-PUB039).
   Retention: tmp_count is static queue length; fifo[1..tmp_count] stays compact on each scan. No explicit reset; only successful edge actions alter valid queue state (PUB001-PUB039).
   Outputs: count := tmp_count; full := tmp_count = 8; empty := tmp_count = 0; head := fifo[1] when nonempty, else 0 (PUB001-PUB039).
   Bounds: count/INT 0..8; fifo indices 1..8. Invalid tail fifo[tmp_count+1..8] is unspecified and not cleared (PUB001-PUB039).
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
    prevPushEn : BOOL := FALSE;
    prevPopEn : BOOL := FALSE;
    tmp_count : INT := 0;
    tmp_pushRise : BOOL;
    tmp_popRise : BOOL;
    tmp_i : INT;
END_VAR

tmp_pushRise := pushEn AND NOT prevPushEn;
tmp_popRise := popEn AND NOT prevPopEn;

IF tmp_popRise THEN
    IF tmp_count > 0 THEN
        IF tmp_count > 1 THEN
            FOR tmp_i := 1 TO tmp_count - 1 DO
                fifo[tmp_i] := fifo[tmp_i + 1];
            END_FOR;
        END_IF;
        tmp_count := tmp_count - 1;
    END_IF;
END_IF;

IF tmp_pushRise THEN
    IF tmp_count < 8 THEN
        tmp_count := tmp_count + 1;
        fifo[tmp_count] := pushItem;
    END_IF;
END_IF;

count := tmp_count;
full := (tmp_count = 8);
empty := (tmp_count = 0);

IF tmp_count > 0 THEN
    head := fifo[1];
ELSE
    head := 0;
END_IF;

prevPushEn := pushEn;
prevPopEn := popEn;

END_FUNCTION_BLOCK