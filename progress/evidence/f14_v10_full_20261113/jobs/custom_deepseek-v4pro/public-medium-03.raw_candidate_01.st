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
    local_triggerR : R_TRIG;
    local_buffer : ARRAY[0..99] OF LREAL;
    local_count : INT := 0;
    local_head : INT := 0;
    local_tail : INT := 0;
    local_sum : LREAL := 0.0;
END_VAR

(*
ENGINEERING_CONTRACT
average: update after accepted sample; holds between samples; reset clears to 0.0; invalid size preserves prior value (PUB001)
windowSizeReached: TRUE when buffered count >= windowSize; recalculated each valid scan; reset clears (PUB004)
error/status: invalid windowSize <1 or >100 sets error=TRUE status=16#8200; otherwise error=FALSE status=16#0000 (PUB003 PUB005 PUB006)
cyclicExecution: sample every scan; trigger has no effect while cyclicExecution=TRUE (PUB001)
trigger: sample on rising edge only when cyclicExecution=FALSE; edge detection runs every scan (PUB002)
reset: clears buffer/count/sum/average/windowSizeReached; then validates windowSize; reset scan does not sample (PUB003)
valid window size 1..100; circular buffer max 100; average = sum/count when count >0 else 0.0 (PUB005)
unspecified: valid windowSize change adapts by dropping oldest or appending to new size without automatic reset (PUB005)
*)
(* CONTRACT_RULES [] *)

BEGIN
    local_triggerR(CLK := trigger);

    IF reset THEN
        local_count := 0;
        local_head := 0;
        local_tail := 0;
        local_sum := 0.0;
        average := 0.0;
        windowSizeReached := FALSE;

        IF windowSize < 1 OR windowSize > 100 THEN
            error := TRUE;
            status := WORD#16#8200;
        ELSE
            error := FALSE;
            status := WORD#16#0000;
        END_IF

        RETURN;
    END_IF

    IF windowSize < 1 OR windowSize > 100 THEN
        error := TRUE;
        status := WORD#16#8200;
        windowSizeReached := FALSE;
        RETURN;
    ELSE
        error := FALSE;
        status := WORD#16#0000;
    END_IF

    WHILE local_count > windowSize DO
        local_sum := local_sum - local_buffer[local_head];
        local_head := (local_head + 1) MOD 100;
        local_count := local_count - 1;
    END_WHILE

    IF cyclicExecution OR local_triggerR.Q THEN
        IF local_count < windowSize THEN
            local_buffer[local_tail] := value;
            local_tail := (local_tail + 1) MOD 100;
            local_count := local_count + 1;
            local_sum := local_sum + value;
        ELSE
            local_sum := local_sum - local_buffer[local_head] + value;
            local_buffer[local_head] := value;
            local_head := (local_head + 1) MOD 100;
            local_tail := local_head;
        END_IF
    END_IF

    IF local_count > 0 THEN
        average := local_sum / INT_TO_LREAL(local_count);
    ELSE
        average := 0.0;
    END_IF

    windowSizeReached := (local_count >= windowSize);
END_FUNCTION_BLOCK