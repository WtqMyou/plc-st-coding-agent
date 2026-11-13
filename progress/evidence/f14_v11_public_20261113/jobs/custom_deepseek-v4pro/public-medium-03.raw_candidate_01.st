FUNCTION_BLOCK FB
VAR_INPUT
    cyclicExecution : BOOL;
    trigger : BOOL;
    value : LREAL;
    windowSize : INT;
    reset : BOOL;
END_VAR
VAR_OUTPUT
    average : LREAL;
    windowSizeReached : BOOL;
    error : BOOL;
    status : WORD;
END_VAR
VAR
    trig_rt : R_TRIG;
    buf : ARRAY[0..99] OF LREAL;
    head : INT := 0;
    count : INT := 0;
    n : INT;
    i : INT;
    idx : INT;
    do_update : BOOL;
    tmp_sum : LREAL;
    tmp_window_valid : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   - average: LREAL, updated only on new value read (cyclic scan or trigger rising edge while cyclicExecution FALSE);
     reset clears to 0.0. Unit: input value unit.
   - windowSizeReached: BOOL, TRUE iff count >= windowSize and window valid; reset clears; invalid window sets FALSE.
   - error/status: combinational; invalid window (windowSize < 1 or > 100) sets error TRUE, status 16#8200;
     otherwise error FALSE, status 16#0000.
   - reset has priority over read; invalid window blocks read and overrides status; no latch.
   - trigger rising edges are ignored while cyclicExecution TRUE.
   - circular buffer capacity 100; changing windowSize does not clear buffer.
*)
(* CONTRACT_RULES [] *)

trig_rt(CLK := trigger);
tmp_window_valid := (windowSize >= 1) AND (windowSize <= 100);

IF reset THEN
    head := 0;
    count := 0;
    average := 0.0;
    windowSizeReached := FALSE;

    IF tmp_window_valid THEN
        error := FALSE;
        status := WORD#16#0000;
    ELSE
        error := TRUE;
        status := WORD#16#8200;
    END_IF;
    RETURN;

ELSIF NOT tmp_window_valid THEN
    error := TRUE;
    status := WORD#16#8200;
    average := 0.0;
    windowSizeReached := FALSE;
    RETURN;

ELSE
    error := FALSE;
    status := WORD#16#0000;
    windowSizeReached := (count >= windowSize);

    do_update := FALSE;
    IF cyclicExecution THEN
        do_update := TRUE;
    ELSIF trig_rt.Q THEN
        do_update := TRUE;
    END_IF;

    IF do_update THEN
        buf[head] := value;
        head := (head + 1) MOD 100;
        IF count < 100 THEN
            count := count + 1;
        END_IF;

        n := count;
        IF n > windowSize THEN
            n := windowSize;
        END_IF;

        IF n = 0 THEN
            average := 0.0;
        ELSE
            tmp_sum := 0.0;
            FOR i := 0 TO n - 1 DO
                idx := (head - n + i) MOD 100;
                IF idx < 0 THEN
                    idx := idx + 100;
                END_IF;
                tmp_sum := tmp_sum + buf[idx];
            END_FOR;
            average := tmp_sum / INT_TO_LREAL(n);
        END_IF;

        windowSizeReached := (count >= windowSize);
    END_IF;
END_IF;

END_FUNCTION_BLOCK