(* ENGINEERING_CONTRACT:
 * Phase activation:
 *   - Phase 0 (IDLE): Initial and idle; no counting, waiting for start
 *   - Phase 1 (HEATING): Active; elapsed increments, transitions to phase 2 on pv>=setpoint
 *   - Phase 2 (HOLDING): Active; elapsed increments, retained until timeout/abort/start
 *   - Phase 3 (COMPLETE): Retention; elapsed/timeout frozen until new start or abort
 *   - Phase 9 (ABORTED): Retention; elapsed/timeout frozen until new start
 *
 * Priority per scan (same-scan order):
 *   1. abortBtn=TRUE  → phase=9, preserve elapsed/timeout
 *   2. startBtn rising edge (no abort) → phase=1, elapsed=0, timeout=FALSE
 *   3. running (no abort, no start edge) → count if prev phase 1/2, else hold
 *
 * Counting:
 *   - Start scan: elapsed=0 (not counted)
 *   - Running scans: elapsed += 1 while prev phase 1 or 2
 *   - maxDuration: positive INT, comparison elapsed >= maxDuration triggers timeout
 *
 * Units: maxDuration in scan cycles, elapsed in scan cycles
 * Reset: Only new start rising edge (with no abort) clears elapsed/timeout
 *)

FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    abortBtn    : BOOL;
    setpoint    : REAL;
    pv          : REAL;
    maxDuration : INT;
END_VAR

VAR_OUTPUT
    elapsed : INT := 0;
    phase   : INT := 0;
    timeout : BOOL := FALSE;
END_VAR

VAR
    prev_startBtn : BOOL := FALSE;
END_VAR

VAR
    startRising : BOOL;
    prev_phase  : INT;
END_VAR

// Detect rising edge of startBtn for this scan
startRising := startBtn AND NOT prev_startBtn;
prev_phase  := phase;

// Priority 1: Abort (highest)
IF abortBtn THEN
    phase := 9;
    // elapsed and timeout are preserved
    prev_startBtn := startBtn;
    RETURN;
END_IF;

// Priority 2: New start rising edge (no abort)
IF startRising THEN
    phase   := 1;
    elapsed := 0;
    timeout := FALSE;
    prev_startBtn := startBtn;
    RETURN;
END_IF;

// Priority 3: Running / frozen states (no abort, no new start edge)
IF prev_phase = 1 OR prev_phase = 2 THEN
    // Running: increment elapsed
    elapsed := elapsed + 1;

    IF elapsed >= maxDuration THEN
        // Timeout: enter complete state
        timeout := TRUE;
        phase   := 3;
    ELSE
        // Not yet timed out: determine phase
        IF pv >= setpoint THEN
            phase := 2;          // pv达标，保持保温
        ELSE
            phase := 1;          // 仍处于升温
        END_IF;
    END_IF;
ELSE
    // Frozen: idle (phase=0), complete (phase=3), or aborted (phase=9)
    // phase and timeout retain their values
END_IF;

prev_startBtn := startBtn;

END_FUNCTION_BLOCK