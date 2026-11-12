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
    faultRising      : R_TRIG;
    validFalling     : R_TRIG;
    prevFault        : BOOL;
    prevValid        : BOOL;
    holdTimer        : TON;
    tmpI             : UINT;
END_VAR

(* ENGINEERING_CONTRACT
 * ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
 * │ OUTPUT STATE TABLE                                                                           │
 * ├─────────────────┬───────────────────────────────────────────────────────────────────────────┤
 * │ THICKNESS_ALARM │ Activation:   rising edge of THICKNESS_FAULT while VALID=TRUE (PUB001)    │
 * │                 │ Retention:    held >= 500 ms via TON; remains TRUE while FAULT persists   │
 * │                 │ Reset:        VALID=FALSE or power-up clears alarm and holding state (PUB004)│
 * │                 │ Same-scan:    if VALID drops mid-scan, alarm OFF regardless of FAULT state│
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Fault_     │ Activation:   FALSE-to-TRUE of FAULT while VALID=TRUE (PUB002)             │
 * │ Counter         │ Retention:    monotonically increasing; never auto-decremented             │
 * │                 │ Reset:        power-up only (PUB005); external callers cannot modify       │
 * │                 │ Boundary:     UINT range; overflow wraps per IEC 61131-3                  │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Runtime_   │ Activation:   CUTTING_RUN AND VALID AND NOT FAULT each scan (PUB003)       │
 * │ Accumulator     │ Retention:    preserved when conditions not met; never auto-cleared       │
 * │                 │ Reset:        power-up only (PUB005); uses LTIME nanoseconds internally   │
 * │                 │ Units:        CycleTime (TIME/ms) converted to LTIME (ns) before add      │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Fault_     │ Activation:   new entry at index 0 on valid fault transition (PUB002)     │
 * │ History[0..4]   │ Shift:        older entries shift toward higher indices (PUB002)           │
 * │                 │ Retention:    five most recent; older beyond index 4 are discarded        │
 * │                 │ Reset:        power-up zeros all five entries (PUB005); read-only to callers│
 * └─────────────────┴───────────────────────────────────────────────────────────────────────────┘
 * 
 * ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
 * │ INPUT BEHAVIOR                                                                               │
 * ├───────────────────────────────┬─────────────────────────────────────────────────────────────┤
 * │ THICKNESS_SIGNAL_VALID=FALSE  │ alarm OFF, timer reset, no fault record, no runtime accum   │
 * │ THICKNESS_SIGNAL_VALID=TRUE   │ normal monitoring; alarm follows FAULT, counter/hist update │
 * │ CUTTING_RUN=FALSE             │ no runtime accumulation (fault monitoring still active)     │
 * │ CycleTime positive assumption │ caller guarantees > T#0s per task spec                     │
 * └───────────────────────────────┴─────────────────────────────────────────────────────────────┘
 * 
 * ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
 * │ TIMING BOUNDARY (PUB001, PUB003)                                                            │
 * │ - 500 ms hold: TON.Q = elapsed >= PT; first satisfying tick = ceil(500ms/1ms) = 500 ticks   │
 * │ - No implicit one-scan delay; timer enable and Q check occur in same invocation            │
 * └─────────────────────────────────────────────────────────────────────────────────────────────┘
 *
 * CONTRACT_RULES [{"kind": "hold_until_reset", "output": "THICKNESS_ALARM", "set_input": "THICKNESS_FAULT", "reset_input": null}]
 *)

(* Power-up initialization: handled by VAR initial values *)

(* Detect rising edge of fault while signal is valid *)
faultRising(CLK := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID AND NOT prevFault);

(* Detect falling edge of VALID to clear alarm and timer *)
validFalling(CLK := prevValid AND NOT THICKNESS_SIGNAL_VALID);

(* Handle signal invalidation: clear alarm and timer holding state *)
IF validFalling.Q THEN
    THICKNESS_ALARM := FALSE;
    holdTimer(IN := FALSE, PT := T#500ms);
END_IF

(* When VALID is FALSE, ensure alarm and timer are cleared *)
IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    holdTimer(IN := FALSE, PT := T#500ms);
END_IF

(* Process fault: activate alarm and record history *)
IF faultRising.Q THEN
    (* Increment fault counter *)
    Slab_Fault_Counter := Slab_Fault_Counter + 1;
    
    (* Shift history: move entries toward higher indices *)
    FOR tmpI := 4 TO 1 BY -1 DO
        Slab_Fault_History[tmpI] := Slab_Fault_History[tmpI - 1];
    END_FOR;
    
    (* Store new fault timestamp at index 0 *)
    Slab_Fault_History[0] := FaultTimestamp;
    
    (* Activate alarm and start hold timer *)
    THICKNESS_ALARM := TRUE;
    holdTimer(IN := TRUE, PT := T#500ms);
END_IF;

(* Maintain alarm while fault persists (after initial 500ms hold) *)
IF holdTimer.Q THEN
    THICKNESS_ALARM := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID;
    holdTimer(IN := THICKNESS_ALARM, PT := T#500ms);
END_IF;

(* Accumulate runtime while cutting normally *)
IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TO_LTIME(CycleTime);
END_IF;

(* Update previous state for edge detection on next scan *)
prevFault := THICKNESS_FAULT;
prevValid := THICKNESS_SIGNAL_VALID;

END_FUNCTION_BLOCK