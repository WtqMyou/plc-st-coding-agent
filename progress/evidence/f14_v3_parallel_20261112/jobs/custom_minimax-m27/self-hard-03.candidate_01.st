FUNCTION_BLOCK FB
VAR_INPUT
    pushEn  : BOOL;
    pushItem: INT;
    popEn   : BOOL;
END_VAR

VAR_INOUT
    fifo : ARRAY[1..8] OF INT;
END_VAR

VAR_OUTPUT
    count : INT;
    full  : BOOL;
    empty : BOOL;
    head  : INT;
END_VAR

VAR
    prevPushEn : BOOL := FALSE;
    prevPopEn  : BOOL := FALSE;
    curCount   : INT  := 0;
    i          : INT;
    risingPush : BOOL;
    risingPop  : BOOL;
END_VAR

(* Detect rising edges *)
risingPush := pushEn AND NOT prevPushEn;
risingPop  := popEn  AND NOT prevPopEn;

(* Update edge memory for next scan *)
prevPushEn := pushEn;
prevPopEn  := popEn;

(* ---- POP (executed first) ---- *)
IF risingPop THEN
    IF curCount > 0 THEN
        (* shift left to remove the oldest element *)
        FOR i := 1 TO curCount - 1 DO
            fifo[i] := fifo[i+1];
        END_FOR;
        curCount := curCount - 1;
    END_IF;
END_IF;

(* ---- PUSH (executed after pop) ---- *)
IF risingPush THEN
    IF curCount < 8 THEN
        curCount := curCount + 1;
        fifo[curCount] := pushItem;
    END_IF;
END_IF;

(* ---- Outputs ---- *)
count := curCount;
full  := (curCount = 8);
empty := (curCount = 0);
head  := IF empty THEN 0 ELSE fifo[1];

END_FUNCTION_BLOCK