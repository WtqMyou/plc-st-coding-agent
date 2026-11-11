FUNCTION_BLOCK FB
VAR_INPUT
    enable     : BOOL;               (* TRUE → update average, FALSE → keep previous *)
    values     : ARRAY[1..8] OF INT; (* sampled raw values (1..8 stations) *)
    count      : INT;                (* number of valid samples this cycle (0..8) *)
    avgEnable  : BOOL;               (* averaging enable – when FALSE keep previous *)
END_VAR
VAR_OUTPUT
    avgOut     : REAL;               (* average output *)
END_VAR
VAR
    lastAvg        : REAL := 0.0;    (* stores the previous average for retention *)
    sum            : DINT;           (* wider type to avoid overflow while summing *)
    i              : INT;
    effectiveCount : INT;            (* count limited to the array size 8 *)
END_VAR

(* ---------------------------------------------------------------
   Compute the arithmetic mean of the first ‘effectiveCount’
   samples when:
      • enable      = TRUE
      • avgEnable   = TRUE
      • count       > 0
   In all other situations the output is held at its previous
   value (lastAvg).  No division‑by‑zero can occur because the
   guard “count > 0” is tested before the division.
   --------------------------------------------------------------- *)
IF enable AND avgEnable AND count > 0 THEN
    (* clip count to the available array length *)
    effectiveCount := count;
    IF effectiveCount > 8 THEN
        effectiveCount := 8;
    END_IF;

    (* sum the first ‘effectiveCount’ values using DINT *)
    sum := 0;
    FOR i := 1 TO effectiveCount DO
        sum := sum + values[i];
    END_FOR;

    (* compute the average as REAL (no rounding) *)
    avgOut    := DINT_TO_REAL(sum) / DINT_TO_REAL(effectiveCount);
    lastAvg   := avgOut;          (* remember for cycles where we keep the value *)
ELSE
    (* keep the previous average *)
    avgOut    := lastAvg;
END_IF;

END_FUNCTION_BLOCK