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
    tmp_trig : R_TRIG;
    local_data : ARRAY[0..99] OF LREAL;
    local_count : INT := 0;
    local_start : INT := 0;
    local_sum_all : LREAL := 0.0;
    local_avg_sum : LREAL;
    local_effective : INT;
    tmp_i : INT;
    tmp_idx : INT;
END_VAR

(* ENGINEERING_CONTRACT
 * average: updated after each accepted sample (PUB001-PUB003); 0.0 until first sample.
 * On reset: history is cleared, average assigned 0.0 and windowSizeReached FALSE.
 * If cyclicExecution is TRUE in the same scan as reset, the current value is then accepted
 * as the first sample of the new window (PUB002). If cyclicExecution is FALSE and a trigger
 * rising edge occurs in the same scan as reset, the current value is accepted (PUB003).
 * windowSizeReached: TRUE when stored sample count >= windowSize (PUB001); cleared on reset
 * and on invalid window.
 * error/status: error=TRUE, status=WORD#16#8200 when windowSize<1 or >100 (PUB004, PUB007);
 * reset with valid window clears to FALSE/WORD#16#0000.
 * sample priority per scan: reset first, invalid-window block second, cyclicExecution TRUE
 * third, trigger rising edge fourth; trigger ignored while cyclicExecution TRUE.
 * state: ring of up to 100 LREAL samples with total sum; invalid window pauses sampling and
 * does not clear history; dynamic window changes average over last windowSize samples.
 * boundaries: valid windowSize 1..100 inclusive; average shares value units.
 *)

(* CONTRACT_RULES [] *)

tmp_trig(CLK := trigger);

IF reset THEN
    local_count := 0;
    local_start := 0;
    local_sum_all := 0.0;
    average := 0.0;
    windowSizeReached := FALSE;
END_IF;

IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := WORD#16#8200;
    windowSizeReached := FALSE;
    RETURN;
ELSE
    error := FALSE;
    status := WORD#16#0000;
END_IF;

IF cyclicExecution THEN
    IF local_count < 100 THEN
        local_data[local_count] := value;
        local_count := local_count + 1;
        local_sum_all := local_sum_all + value;
    ELSE
        local_sum_all := local_sum_all - local_data[local_start] + value;
        local_data[local_start] := value;
        local_start := (local_start + 1) MOD 100;
    END_IF;
ELSIF tmp_trig.Q THEN
    IF local_count < 100 THEN
        local_data[local_count] := value;
        local_count := local_count + 1;
        local_sum_all := local_sum_all + value;
    ELSE
        local_sum_all := local_sum_all - local_data[local_start] + value;
        local_data[local_start] := value;
        local_start := (local_start + 1) MOD 100;
    END_IF;
END_IF;

local_avg_sum := local_sum_all;

IF local_count > windowSize THEN
    FOR tmp_i := 0 TO (local_count - windowSize - 1) DO
        tmp_idx := (local_start + tmp_i) MOD 100;
        local_avg_sum := local_avg_sum - local_data[tmp_idx];
    END_FOR;
END_IF;

local_effective := local_count;
IF local_effective > windowSize THEN
    local_effective := windowSize;
END_IF;

IF local_effective > 0 THEN
    average := local_avg_sum / INT_TO_LREAL(local_effective);
ELSE
    average := 0.0;
END_IF;

windowSizeReached := local_count >= windowSize;

END_FUNCTION_BLOCK