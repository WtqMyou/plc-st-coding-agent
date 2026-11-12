FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    rawValue : REAL;
END_VAR
VAR_OUTPUT
    filteredValue : REAL;
    windowFull : BOOL;
    sampleCount : INT;
END_VAR
VAR
    local_data : ARRAY[0..7] OF REAL;
    local_count : INT := 0;
    local_writeIdx : INT := 0;
    local_sum : REAL;
    local_idx : INT;
    local_filtered : REAL := 0.0;
END_VAR

(* ENGINEERING_CONTRACT
  [PUB001-PUB003] enable TRUE: insert rawValue into 8-slot FIFO.
  [PUB004-PUB008] count=min(8,prev+1); unfilled slots ignored.
  [PUB009-PUB012] full: replace oldest slot and rotate write index.
  [PUB013-PUB016] sampleCount=count 0..8; windowFull=(count=8).
  [PUB017-PUB020] enable FALSE: clear history, count=0, full=FALSE,
      filteredValue held from last computation.
  [S1-S7] average over first count slots; boundaries strict; output at end.
*)

(* CONTRACT_RULES [] *)

IF enable THEN
    IF local_count < 8 THEN
        local_data[local_count] := rawValue;
        local_count := local_count + 1;
        local_writeIdx := local_count MOD 8;
    ELSE
        local_data[local_writeIdx] := rawValue;
        local_writeIdx := (local_writeIdx + 1) MOD 8;
    END_IF;

    sampleCount := local_count;
    windowFull := (local_count = 8);

    local_sum := 0.0;
    FOR local_idx := 0 TO local_count - 1 DO
        local_sum := local_sum + local_data[local_idx];
    END_FOR;

    local_filtered := local_sum / INT_TO_REAL(local_count);
    filteredValue := local_filtered;
ELSE
    local_count := 0;
    local_writeIdx := 0;
    sampleCount := 0;
    windowFull := FALSE;

    FOR local_idx := 0 TO 7 DO
        local_data[local_idx] := 0.0;
    END_FOR;

    filteredValue := local_filtered;
END_IF;
END_FUNCTION_BLOCK