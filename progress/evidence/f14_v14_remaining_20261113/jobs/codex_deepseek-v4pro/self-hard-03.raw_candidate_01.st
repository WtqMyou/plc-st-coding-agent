(* CONTRACT_RULES [] *)
(* ENGINEERING_CONTRACT
  [PUB001] Capacity 8; inputs act only on FALSE->TRUE; initial count=0.
  [PUB002] popEn rising executes first: if count>0 shift fifo[1..7] left by one, decrement.
  [PUB003] pushEn rising executes second: if count<8 write fifo[count+1]=pushItem, increment.
  [PUB004] Same scan uses popped result; pop before push. Empty both => one item. Full both => replace one.
  [PUB005] count 0..8; full<=>count=8; empty<=>count=0.
  [PUB006] head=0 when empty, else head=fifo[1].
  [PUB007] fifo[1..count] remains compact in dequeue order; invalid tail unspecified.
  [PUB008] Retention: no successful operation preserves count and fifo[1..count]; push rejection preserves queue.
*)
FUNCTION_BLOCK FB
VAR_INPUT
    pushEn   : BOOL;
    pushItem : INT;
    popEn    : BOOL;
END_VAR
VAR_OUTPUT
    count : INT := 0;
    full  : BOOL := FALSE;
    empty : BOOL := TRUE;
    head  : INT := 0;
END_VAR
VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR
VAR
    local_push_prev : BOOL := FALSE;
    local_pop_prev  : BOOL := FALSE;
    local_push_rise : BOOL;
    local_pop_rise  : BOOL;
    local_count     : INT;
    local_i         : INT;
END_VAR

local_push_rise := pushEn AND NOT local_push_prev;
local_pop_rise  := popEn AND NOT local_pop_prev;

local_count := count;

IF local_pop_rise AND (local_count > 0) THEN
    FOR local_i := 1 TO 7 DO
        fifo[local_i] := fifo[local_i + 1];
    END_FOR;
    local_count := local_count - 1;
END_IF;

IF local_push_rise AND (local_count < 8) THEN
    fifo[local_count + 1] := pushItem;
    local_count := local_count + 1;
END_IF;

count := local_count;
full  := (count = 8);
empty := (count = 0);

IF count = 0 THEN
    head := 0;
ELSE
    head := fifo[1];
END_IF;

local_push_prev := pushEn;
local_pop_prev  := popEn;

END_FUNCTION_BLOCK