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
    faultRising  : R_TRIG;
    validFalling : R_TRIG;
    prevFault    : BOOL;
    prevValid    : BOOL;
    holdTimer    : TON;
    holdActive   : BOOL;
    tmpI         : UINT;
END_VAR

(* ENGINEERING_CONTRACT
 * ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
 * │ OUTPUT STATE TABLE                                                                           │
 * ├─────────────────┬───────────────────────────────────────────────────────────────────────────┤
 * │ THICKNESS_ALARM │ Activation:   immediate on FALSE-to-TRUE of FAULT while VALID=TRUE        │
 * │                 │ Retention:    holds TRUE for >= 500ms; then follows FAULT (PUB001)       │
 * │                 │ Reset:        VALID=FALSE clears alarm+hold; power-up clears (PUB004)    │
 * │                 │ Same-scan:    on VALID=FALSE, alarm OFF immediately; holdActive cleared  │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Fault_     │ Activation:   FALSE-to-TRUE of FAULT while VALID=TRUE (PUB002)            │
 * │ Counter         │ Retention:    monotonically increasing; never auto-decremented           │
 * │                 │ Reset:        power-up only (PUB005)                                     │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Runtime_   │ Activation:   CUTTING_RUN AND VALID AND NOT FAULT each scan (PUB003)     │
 * │ Accumulator     │ Retention:    preserved when conditions not met                          │
 * │                 │ Reset:        power-up only (PUB005)                                     │
 * │                 │ Units:        LTIME nanoseconds; CycleTime TIME converted via TO_LTIME   │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Fault_     │ Activation:   new entry at index 0 on valid fault transition (PUB002)    │
 * │ History[0..4]   │ Shift:        older entries shift toward higher indices (PUB002)          │
 * │                 │ Retention:    five most recent; read-only to callers (PUB005)            │
 * │                 │ Reset:        power-up only (PUB005)                                     │
 * └─────────────────┴───────────────────────────────────────────────────────────────────────────┘
 *
 * ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
 * │ TIMING BOUNDARY (PUB001)                                                                    │
 * │ - 500ms minimum hold: TON.Q = elapsed >= PT; first satisfying tick = 500 ticks @ 1ms       │
 * │ - holdActive ensures timer runs exactly once per fault; no continuous re-triggering        │
 * └─────────────────────────────────────────────────────────────────────────────────────────────┘
 *
 * CONTRACT_RULES []
 *)

(* Power-up initialization: VAR initial values handle all state to zero *)

(* Detect rising edge of fault while signal is valid *)
faultRising(CLK := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT AND NOT prevFault);

(* Detect falling edge of VALID *)
validFalling(CLK := prevValid AND NOT THICKNESS_SIGNAL_VALID);

(* Clear alarm and hold state when signal lost or invalidated *)
IF validFalling.Q OR NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    holdActive      := FALSE;
    holdTimer(IN := FALSE, PT := T#500ms);
END_IF;

(* Process new fault: activate alarm and start 500ms hold timer *)
IF faultRising.Q THEN
    Slab_Fault_Counter := Slab_Fault_Counter + 1;
    
    FOR tmpI := 4 TO 1 BY -1 DO
        Slab_Fault_History[tmpI] := Slab_Fault_History[tmpI - 1];
    END_FOR;
    Slab_Fault_History[0] := FaultTimestamp;
    
    THICKNESS_ALARM := TRUE;
    holdActive      := TRUE;
    holdTimer(IN := TRUE, PT := T#500ms);
END_IF;

(* After 500ms hold completes, let alarm follow fault state *)
IF holdTimer.Q AND holdActive THEN
    holdActive := FALSE;
    holdTimer(IN := FALSE, PT := T#500ms);
    THICKNESS_ALARM := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID;
END_IF;

(* Accumulate normal-cutting runtime *)
IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TO_LTIME(CycleTime);
END_IF;

(* Update previous state for next-scan edge detection *)
prevFault := THICKNESS_FAULT;
prevValid := THICKNESS_SIGNAL_VALID;

END_FUNCTION_BLOCK