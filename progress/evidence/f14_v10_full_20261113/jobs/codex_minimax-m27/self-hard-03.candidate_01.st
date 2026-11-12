(* ENGINEERING_CONTRACT
| Output/State    | Activation        | Retention         | Explicit Reset | Scan Priority | Units/Boundaries |
|-----------------|-------------------|-------------------|----------------|---------------|------------------|
| count           | Computed each scan| Maintained        | None           | After ops     | 0..8 integer     |
| full            | count=8           | Held until count<8| None           | With count    | BOOL             |
| empty           | count=0           | Held until count>0| None           | With count    | BOOL             |
| head            | fifo[1] or 0      | Held on empty     | None           | After ops     | INT              |
| fifo[1..count]  | Compacted each scan| Retained         | None           | After ops     | ARRAY[1..8] INT  |

PUB001: pushEn (rising edge trigger)
PUB002: pushItem (INT payload)
PUB003: popEn (rising edge trigger)
PUB004: fifo INOUT ARRAY[1..8] INT, caller-bound, read-write during scan
PUB005: count = length 0..8
PUB006: full <-> count=8
PUB007: empty <-> count=0
PUB008: head = fifo[1] when !empty else 0
PUB009: pop on rising(popEn) executes first if count>0
PUB010: push on rising(pushEn) executes second if count<8
PUB011: same-scan full+pop+push: pop frees slot then push appends
PUB012: same-scan empty+pop+push: only push adds item
PUB013: fifo[1..count] compact, fifo[1]=head when !empty
PUB014: undefined fifo[count+1..8]
PUB015: initial count=0, empty=TRUE, fifo[1..8] undefined
PUB016: rising edge = prev=FALSE AND cur=TRUE
PUB017: sustained press does not repeat (edge-only)
PUB018: R_TRIG used for edge memory
PUB019: scan-order: detect edges, execute pop, execute push, compute outputs
PUB020: CONTRACT_RULES []

Function Block FB
VAR_INPUT
    pushEn : BOOL;
    pushItem : INT;
    popEn : BOOL;
END_VAR
VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR
VAR_OUTPUT
    count : INT := 0;
    full : BOOL := FALSE;
    empty : BOOL := TRUE;
    head : INT := 0;
END_VAR
VAR
    pushTrig : R_TRIG;
    popTrig : R_TRIG;
END_VAR

pushTrig(CLK := pushEn);
popTrig(CLK := popEn);

IF popTrig.Q AND count > 0 THEN
    FOR i := 1 TO count - 1 DO
        fifo[i] := fifo[i + 1];
    END_FOR;
    count := count - 1;
END_IF;

IF pushTrig.Q AND count < 8 THEN
    count := count + 1;
    fifo[count] := pushItem;
END_IF;

full := (count = 8);
empty := (count = 0);
head := 0;
IF NOT empty THEN
    head := fifo[1];
END_IF;

END_FUNCTION_BLOCK