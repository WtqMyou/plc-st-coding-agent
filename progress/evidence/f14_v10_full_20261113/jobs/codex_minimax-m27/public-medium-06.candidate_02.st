FUNCTION_BLOCK SlabThicknessMonitor
VAR_INPUT
    THICKNESS_FAULT        : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN            : BOOL;
    FaultTimestamp         : DINT;
    CycleTime              : TIME;
END_VAR

VAR_OUTPUT
    THICKNESS_ALARM          : BOOL;
    Slab_Fault_Counter       : UINT;
    Slab_Runtime_Accumulator : LTIME;
    Slab_Fault_History       : ARRAY[0..4] OF DINT;
END_VAR

VAR
    faultRising : R_TRIG;
    prevFault   : BOOL;
    prevValid   : BOOL;
    holdTimer   : TON;
    tmpI        : UINT;
END_VAR

(* ENGINEERING_CONTRACT
 * ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
 * │ OUTPUT STATE TABLE                                                                           │
 * ├─────────────────┬───────────────────────────────────────────────────────────────────────────┤
 * │ THICKNESS_ALARM │ Activation:   immediate on rising edge of FAULT while VALID=TRUE (PUB001) │
 * │                 │ Retention:    hold >= 500ms via TON after FAULT drops; persists if FAULT │
 * │                 │               remains TRUE                                                │
 * │                 │ Reset:        VALID=FALSE clears alarm and timer holding state (PUB004)   │
 * │                 │ Same-scan:    alarm OFF immediately when VALID drops                      │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Fault_     │ Activation:   FALSE-to-TRUE of FAULT while VALID=TRUE (PUB002)            │
 * │ Counter         │ Retention:    monotonically increasing; never auto-decremented            │
 * │                 │ Reset:        power-up only (PUB005)                                      │
 * │                 │ Boundary:     UINT range                                                  │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Runtime_   │ Activation:   CUTTING_RUN AND VALID AND NOT FAULT AND NOT faultRising     │
 * │ Accumulator     │               (excludes scan where fault just transitioned TRUE) (PUB003) │
 * │                 │ Retention:    preserved when conditions not met                           │
 * │                 │ Reset:        power-up only (PUB005)                                      │
 * │                 │ Units:        CycleTime converted to LTIME ns before add                  │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Fault_     │ Activation:   new entry at index 0 on valid fault transition (PUB002)     │
 * │ History[0..4]   │ Shift:        older entries shift toward higher indices (PUB002)          │
 * │                 │ Retention:    five most recent; older beyond index 4 discarded            │
 * │                 │ Reset:        power-up zeros all five entries (PUB005)                    │
 * └─────────────────┴───────────────────────────────────────────────────────────────────────────┘
 * 
 * ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
 * │ TIMING BOUNDARY (PUB001)                                                                    │
 * │ - 500ms hold: TON.Q = elapsed >= PT; first satisfying tick = 500 ticks at 1ms quantum      │
 * │ - Alarm reactivates immediately via R_TRIG on same-scan FAULT transitions                  │
 * │ - Timer resets when alarm deactivates to prevent stale elapsed time                        │
 * └─────────────────────────────────────────────────────────────────────────────────────────────┘
 *
 * CONTRACT_RULES [{"kind": "hold_until_reset", "output": "THICKNESS_ALARM", "set_input": "THICKNESS_FAULT", "reset_input": null}]
 *)

(* Power-up initialization: VAR initial values handle zeroing *)

(* Detect rising edge of fault while signal is valid *)
faultRising(CLK := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID AND NOT prevFault);

(* Clear alarm and timer when signal becomes invalid *)
IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    holdTimer(IN := FALSE, PT := T#500ms);
END_IF;

(* Activate alarm immediately on valid fault rising edge *)
IF faultRising.Q THEN
    THICKNESS_ALARM := TRUE;
    holdTimer(IN := TRUE, PT := T#500ms);
END_IF;

(* Maintain alarm while fault persists after initial hold *)
IF holdTimer.Q THEN
    THICKNESS_ALARM := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID;
    holdTimer(IN := THICKNESS_ALARM, PT := T#500ms);
END_IF;

(* Record fault: increment counter and shift history *)
IF faultRising.Q THEN
    Slab_Fault_Counter := Slab_Fault_Counter + 1;
    FOR tmpI := 4 TO 1 BY -1 DO
        Slab_Fault_History[tmpI] := Slab_Fault_History[tmpI - 1];
    END_FOR;
    Slab_Fault_History[0] := FaultTimestamp;
END_IF;

(* Accumulate runtime only while cutting normally (excludes fault-transition scan) *)
IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT AND NOT faultRising.Q THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TO_LTIME(CycleTime);
END_IF;

(* Update previous state for edge detection *)
prevFault := THICKNESS_FAULT;
prevValid := THICKNESS_SIGNAL_VALID;

END_FUNCTION_BLOCK