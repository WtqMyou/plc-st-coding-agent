(* ENGINEERING_CONTRACT
 * FIFO Queue with 8-slot compact array
 * [PUB001-PUB010] Core ops: popEn rising→remove first if count>0; pushEn rising→add pushItem if count<8
 *   Same-scan priority: pop executes BEFORE push; full→pop+push (net 0), empty→push-only (net +1)
 * [PUB011] Retention: count and fifo[1..8] state retained in VAR between scans
 * [PUB012] No AT located declarations
 * [PUB013-PUB015] Rising edge: each button triggers once per press; initial history=FALSE
 * [PUB016-PUB019] Same-scan semantics: full queue drains one slot then accepts push; empty queue accepts push only
 * [PUB020-PUB025] Array bounds: fifo[1..8], compact at end of scan: fifo[1..count] is logical queue FIFO order
 *   head=fifo[1] when non-empty, else 0; fifo[count+1..8] unspecified/unconstrained
 * [PUB026-PUB030] count∈[0,8], full↔count=8, empty↔count=0; success of push/pop updates count
 *)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    pushEn    : BOOL;
    pushItem  : INT;
    popEn     : BOOL;
END_VAR
VAR_IN_OUT
    fifo      : ARRAY[1..8] OF INT;
END_VAR
VAR_OUTPUT
    count     : INT;
    full      : BOOL;
    empty     : BOOL;
    head      : INT;
END_VAR
VAR
    prev_pushEn : BOOL := FALSE;
    prev_popEn  : BOOL := FALSE;
    tmp_pushRising : BOOL;
    tmp_popRising  : BOOL;
    tmp_i       : INT;
END_VAR

    // Rising edge detection
    tmp_popRising  := popEn AND NOT prev_popEn;
    tmp_pushRising := pushEn AND NOT prev_pushEn;
    prev_popEn  := popEn;
    prev_pushEn := pushEn;

    // Execute in required order: pop first, then push
    // POP: non-empty queue only
    IF tmp_popRising AND count > 0 THEN
        FOR tmp_i := 1 TO count - 1 DO
            fifo[tmp_i] := fifo[tmp_i + 1];
        END_FOR;
        count := count - 1;
    END_IF;

    // PUSH: non-full queue only
    IF tmp_pushRising AND count < 8 THEN
        count := count + 1;
        fifo[count] := pushItem;
    END_IF;

    // Outputs
    full  := (count = 8);
    empty := (count = 0);
    IF empty THEN
        head := 0;
    ELSE
        head := fifo[1];
    END_IF;

END_FUNCTION_BLOCK