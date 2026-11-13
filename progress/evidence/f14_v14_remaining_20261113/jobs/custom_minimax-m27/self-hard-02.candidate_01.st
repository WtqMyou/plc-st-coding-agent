FUNCTION_BLOCK FB
VAR_INPUT
    startBtn   : BOOL;
    abortBtn   : BOOL;
    setpoint   : REAL;
    pv         : REAL;
    maxDuration: INT;
END_VAR
VAR_OUTPUT
    elapsed : INT := 0;
    phase   : INT := 0;
    timeout : BOOL := FALSE;
END_VAR
VAR
    prev_startBtn : BOOL := FALSE;
    prev_abortBtn : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
  PUB001-003: Initial (phase,elapsed,timeout)=(0,0,FALSE) on cold-start.
  PUB004:    maxDuration is a positive integer scan-count threshold.
  PUB005-006: Priority order per scan: (1) abort, (2) new start rising edge,
              (3) running count. No external clock or TON used.
  PUB007:    abortBtn=TRUE  → phase=9 immediately; elapsed & timeout frozen.
             A consumed rising edge cannot re-trigger without a release-press.
  PUB008:    New start rising edge (no abort) → phase=1,elapsed=0,timeout=FALSE.
             Start scan does NOT increment elapsed.
  PUB009:    When prev phase∈{1,2}: elapsed += 1 first, then threshold check.
  PUB010:    If elapsed >= maxDuration → timeout=TRUE, phase=3 (takes priority
             over pv/setpoint check). Else if pv>=setpoint → phase=2, else phase=1.
  PUB011-012: phase=3 (complete) and phase=9 (aborted) freeze elapsed & timeout
              until a new valid start or abort event.
  S1-S5/N10-S1..S6: All formal properties encoded in conditional branches.
  Units: elapsed in scan-pairs; maxDuration in scan-pairs; no time dimension.
*)
(* CONTRACT_RULES
  []
*)

VAR
    tmp_risingStart : BOOL;
    tmp_risingAbort : BOOL;
    tmp_wasRunning  : BOOL;
    tmp_prevPhase   : INT;
    tmp_prevTimeout : BOOL;
END_VAR

tmp_risingStart := startBtn AND NOT prev_startBtn;
tmp_risingAbort := abortBtn  AND NOT prev_abortBtn;
tmp_prevPhase   := phase;
tmp_prevTimeout := timeout;

IF tmp_risingAbort THEN
    // PUB007: abort priority over same-scan rising start; freeze counters
    phase   := 9;
    // elapsed, timeout unchanged
ELSIF tmp_risingStart THEN
    // PUB008: new batch, start scan not counted
    phase    := 1;
    elapsed  := 0;
    timeout  := FALSE;
ELSIF (tmp_prevPhase = 1) OR (tmp_prevPhase = 2) THEN
    // PUB009: running phase → increment elapsed, then evaluate timeout/transition
    elapsed := elapsed + 1;
    IF elapsed >= maxDuration THEN
        // PUB010: timeout reached → complete; pv check skipped
        timeout := TRUE;
        phase   := 3;
    ELSIF pv >= setpoint THEN
        phase := 2;
    ELSE
        phase := 1;
    END_IF;
ELSIF (tmp_prevPhase = 3) OR (tmp_prevPhase = 9) THEN
    // PUB011-012: terminal states retain counters
    phase   := tmp_prevPhase;
    timeout := tmp_prevTimeout;
ELSE
    // idle (phase=0) with no start edge: hold state
    phase   := 0;
END_IF;

prev_startBtn := startBtn;
prev_abortBtn := abortBtn;
END_FUNCTION_BLOCK