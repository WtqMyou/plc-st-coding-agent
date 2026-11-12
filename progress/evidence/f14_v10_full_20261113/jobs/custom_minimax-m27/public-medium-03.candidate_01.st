FUNCTION_BLOCK FB_MovingAverage
VAR_INPUT
    cyclicExecution : BOOL;
    trigger         : BOOL;
    value           : LREAL;
    windowSize      : INT;
    reset           : BOOL;
END_VAR

VAR_OUTPUT
    average           : LREAL := 0.0;
    windowSizeReached : BOOL  := FALSE;
    error             : BOOL  := FALSE;
    status            : WORD  := 16#0000;
END_VAR

VAR
    trigger_r     : R_TRIG;
    tmp_buffer    : ARRAY[1..100] OF LREAL;
    tmp_sum       : LREAL := 0.0;
    tmp_count     : INT   := 0;
    tmp_writeIdx  : INT   := 1;
END_VAR

(* ENGINEERING_CONTRACT
  | Output/State   | Activation          | Retention/Hold       | Reset/Deactivation  | Priority   | Units/Bounds          |
  |----------------|---------------------|----------------------|---------------------|------------|-----------------------|
  | average        | cyclicExecution=TRUE| HOLD: retains value  | reset=TRUE sets 0.0 | Same-scan | LREAL; sliding mean   |
  | (continued)    | OR trigger rising   | on same scan if no   | when window invalid | as trigger | 1..100 element window |
  |                | edge (non-cyclic)   | new value processed  |                     |            |                       |
  | windowSize     | Same as average     | HOLD: TRUE retained  | reset=TRUE sets     | Same-scan | BOOL; TRUE when       |
  | Reached        |                     | when not updated     | FALSE               | as trigger | tmp_count>=windowSize |
  | error          | windowSize<1 or     | HOLD: TRUE until     | reset=TRUE clears   | Precedes  | TRUE when windowSize  |
  |                | windowSize>100      | valid window set     | (valid WS) or reset | processing | outside [1,100]       |
  | status         | Same as error       | HOLD: 16#8200 until  | reset=TRUE clears   | Precedes  | 16#0000=OK;          |
  |                |                     | valid window set     | (valid WS) or reset | processing | 16#8200=WS error      |
  |----------------|---------------------|----------------------|---------------------|------------|-----------------------|
  PUB001: Sliding arithmetic mean replaces oldest datum with newest on each read.
  PUB002: cyclicExecution=TRUE updates average every scan cycle; trigger ignored.
  PUB003: Rising edge on trigger (non-cyclic) reads one value and updates average.
  PUB004: reset=TRUE (level) clears buffer/sum/count/index and sets outputs to idle.
  PUB004: Invalid windowSize (<1 or >100) sets error=TRUE and status=16#8200.
  PUB005: windowSizeReached=FALSE until tmp_count reaches windowSize.
  PUB006: error=TRUE when windowSize validation fails; cleared on valid size.
  PUB007: status=16#0000 (success) or 16#8200 (window size error 1..100 only).
*)

trigger_r(CLK := trigger);

IF reset THEN
    tmp_count    := 0;
    tmp_sum      := 0.0;
    tmp_writeIdx := 1;
    average           := 0.0;
    windowSizeReached := FALSE;
    error             := FALSE;
    status            := 16#0000;
    RETURN;
END_IF;

IF windowSize < 1 OR windowSize > 100 THEN
    error  := TRUE;
    status := 16#8200;
    RETURN;
END_IF;

IF tmp_count > windowSize THEN
    tmp_count    := 0;
    tmp_sum      := 0.0;
    tmp_writeIdx := 1;
END_IF;

IF cyclicExecution OR trigger_r.Q THEN
    IF tmp_count >= windowSize THEN
        tmp_sum := tmp_sum - tmp_buffer[tmp_writeIdx];
    ELSE
        tmp_count := tmp_count + 1;
    END_IF;

    tmp_buffer[tmp_writeIdx] := value;
    tmp_sum := tmp_sum + value;

    tmp_writeIdx := (tmp_writeIdx MOD windowSize) + 1;

    average := tmp_sum / LREAL(tmp_count);
    windowSizeReached := (tmp_count >= windowSize);
    error  := FALSE;
    status := 16#0000;
END_IF;

END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)