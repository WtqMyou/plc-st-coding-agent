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
    pushPrev : BOOL;
    popPrev : BOOL;
    pushEdge : BOOL;
    popEdge : BOOL;
    i : INT;
END_VAR

(* Detect each button edge independently; pop precedes push. *)
pushEdge := pushEn AND NOT pushPrev;
popEdge := popEn AND NOT popPrev;
pushPrev := pushEn;
popPrev := popEn;

(* The contract requires compact visible storage, not only correct pointers. *)
IF popEdge AND count > 0 THEN
    FOR i := 1 TO 7 DO
        fifo[i] := fifo[i + 1];
    END_FOR
    count := count - 1;
END_IF
IF pushEdge AND count < 8 THEN
    count := count + 1;
    fifo[count] := pushItem;
END_IF
FOR i := 1 TO 8 DO
    IF i > count THEN fifo[i] := 0; END_IF
END_FOR
full := count >= 8;
empty := count <= 0;
IF empty THEN head := 0; ELSE head := fifo[1]; END_IF
END_FUNCTION_BLOCK
