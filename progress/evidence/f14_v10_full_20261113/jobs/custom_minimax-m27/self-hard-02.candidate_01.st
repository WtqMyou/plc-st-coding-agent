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
    tmp_startPrev : BOOL := FALSE;
    tmp_phase     : INT  := 0;
    trackedPhase  : INT  := 0;
END_VAR
VAR_TEMP
    tmp_risingEdge : BOOL;
END_VAR
(* ENGINEERING_CONTRACT
  Interface contract (per PUB IDs):
  - PUB001: Initial (phase,elapsed,timeout) = (0,0,FALSE) via VAR_INIT.
  - PUB003/PUB004: maxDuration positive INT, finite REALs; no timers/clocks.
  - PUB006/PUB007/PUB008: Per-scan priority: abort > new start rising edge >
    running count. abortBtn TRUE → phase=9 immediately, same-scan start edge
    consumed, re-start requires release+press.
  - PUB009: No abort + new start rising edge → phase=1, elapsed=0, timeout=FALSE;
    start scan not counted.
  - PUB010/PUB011/PUB012: Running state (phase=1 or 2): elapsed increments first,
    then timeout check at updated value (>= maxDuration → phase=3, timeout=TRUE,
    priority over pv/setpoint). Phase transition pv>=setpoint during phase=1
    enters phase=2; phase=2 holds until timeout/abort/new start.
  - PUB013/PUB014: phase=3 (completion) and phase=9 (abort) freeze elapsed and
    timeout until new valid start or abort. No operator acknowledgment.
  Output retention: phase/elapsed/timeout are held in terminal states per S4/N10-S4.
  Same-scan priority: abort evaluated first; start rising edge consumed when abort
    TRUE; timeout check evaluated after elapsed increment and takes priority over
    pv-based phase=2 transition per PUB011.
  Boundary: elapsed>=maxDuration (>= not >) triggers timeout; start scan elapsed=0
    (no increment that scan); trackedPhase preserves same-scan phase context for
    pv evaluation in phase=2 maintenance rule.
*)
BEGIN
    (* Rising edge detection for startBtn (deferred when abort TRUE) *)
    tmp_risingEdge := startBtn AND NOT tmp_startPrev;

    (* Priority 1: abort → phase=9, freeze elapsed & timeout *)
    IF abortBtn THEN
        phase   := 9;
        tmp_phase := phase;
        trackedPhase := phase;
        (* Do NOT update tmp_startPrev; rising edge is consumed per PUB006 *)
    (* Priority 2: new start rising edge → begin new batch *)
    ELSIF tmp_risingEdge THEN
        elapsed     := 0;
        timeout     := FALSE;
        phase       := 1;
        tmp_phase   := phase;
        trackedPhase := phase;
        tmp_startPrev := startBtn;
    (* Priority 3: steady-state running count and phase logic *)
    ELSE
        (* Running state: count one scan, then check timeout, then pv/setpoint *)
        IF (tmp_phase = 1) OR (tmp_phase = 2) THEN
            elapsed := elapsed + 1;
            (* PUB011: timeout check at updated elapsed; priority over pv/setpoint *)
            IF elapsed >= maxDuration THEN
                timeout     := TRUE;
                phase       := 3;
                tmp_phase   := phase;
                trackedPhase := phase;
            ELSIF trackedPhase = 2 OR pv >= setpoint THEN
                phase       := 2;
                tmp_phase   := phase;
                trackedPhase := phase;
            ELSE
                phase       := 1;
                tmp_phase   := phase;
                trackedPhase := phase;
            END_IF;
        ELSE
            (* Idle/completion/abort: hold phase, elapsed, timeout *)
            phase       := tmp_phase;
            trackedPhase := phase;
        END_IF;
        tmp_startPrev := startBtn;
    END_IF;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)