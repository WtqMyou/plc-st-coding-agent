(* ENGINEERING_CONTRACT
 * Design table for FB averaging function block:
 *
 * | Output/State  | Activation event             | Retention/hold                  | Explicit reset | Same-scan priority | Units/boundaries      |
 * |---------------|-------------------------------|---------------------------------|----------------|--------------------|-----------------------|
 * | avgOut update | enable AND avgEnable AND      | Hold on: !enable, !avgEnable,   | None stated    | Combinational      | Real, no rounding     |
 * |               | count > 0                     | count <= 0                      |                | override            |                       |
 * | Division      | Only when count > 0 AND       | N/A (blocked)                   | N/A            | N/A                 | Divisor: clamped 1..8 |
 * |               | entering compute branch       |                                 |                |                    |                       |
 * | Sum overflow  | Any valid compute scan        | N/A                             | N/A            | N/A                 | DINT accumulator      |
 *
 * Clause references:
 * - PUB001: enable gate for update
 * - PUB003: count gating, 0..8 range
 * - PUB005: no division by zero
 * - PUB006: count > 8 clamped to 8
 * - PUB007: avgEnable gate
 * - PUB008: DINT sum to avoid overflow
 * - PUB010: REAL output, no rounding
 *
 * Boundary arithmetic:
 * - count = 0: no compute, avgOut held
 * - count = 1..8: compute exactly that many elements
 * - count > 8: compute exactly 8 elements
 * - count < 0: same as count = 0 (held), no negative indexing
 *)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    enable    : BOOL;
    values    : ARRAY[1..8] OF INT;
    count     : INT;
    avgEnable : BOOL;
END_VAR

VAR_OUTPUT
    avgOut : REAL;
END_VAR

VAR
    tmp_sum    : DINT;
    tmp_count  : INT;
    i          : INT;
END_VAR

// Compute average only when all gates are active and count is positive
IF enable AND avgEnable AND (count > 0) THEN
    // Clamp effective count to array upper bound
    IF count >= 8 THEN
        tmp_count := 8;
    ELSE
        tmp_count := count;
    END_IF;

    // Accumulate using DINT to prevent INT overflow
    tmp_sum := 0;
    FOR i := 1 TO tmp_count DO
        tmp_sum := tmp_sum + values[i];
    END_FOR;

    // Real division with no rounding
    avgOut := DINT_TO_REAL(tmp_sum) / INT_TO_REAL(tmp_count);
END_IF;
// All other cases: avgOut retains previous value (no assignment)
// Including: !enable, !avgEnable, count <= 0, count < 0
END_FUNCTION_BLOCK