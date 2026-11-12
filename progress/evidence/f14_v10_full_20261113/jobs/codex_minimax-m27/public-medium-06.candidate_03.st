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
    validFalling : F_TRIG;
    prevFault    : BOOL;
    prevValid    : BOOL;
    holdTimer    : TON;
    latch        : BOOL;
    inHoldPhase  : BOOL;
    tmpI         : UINT;
END_VAR

(* ENGINEERING_CONTRACT
 * ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
 * │ OUTPUT STATE TABLE                                                                           │
 * ├─────────────────┬───────────────────────────────────────────────────────────────────────────┤
 * │ THICKNESS_ALARM │ Activation:   immediate on rising edge of FAULT while VALID=TRUE (PUB001) │
 * │                 │ Retention:    held >= 500ms via TON; remains TRUE while FAULT persists   │
 * │                 │ Reset:        VALID=FALSE clears latch and timer (PUB004)                 │
 * │                 │ Same-scan:    latch set and timer started in same invocation as rising edge│
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Fault_     │ Activation:   FALSE-to-TRUE of FAULT while VALID=TRUE (PUB002)            │
 * │ Counter         │ Retention:    monotonically increasing; never auto-decremented            │
 * │                 │ Reset:        power-up only (PUB005)                                     │
 * │                 │ Boundary:     UINT range; overflow wraps per IEC 61131-3                 │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Runtime_   │ Activation:   CUTTING_RUN AND VALID AND NOT FAULT each scan (PUB003)      │
 * │ Accumulator     │ Retention:    preserved when conditions not met; never auto-cleared      │
 * │                 │ Reset:        power-up only (PUB005)                                     │
 * │                 │ Units:        CycleTime (TIME) converted to LTIME (ns) before add        │
 * ├─────────────────┼───────────────────────────────────────────────────────────────────────────┤
 * │ Slab_Fault_     │ Activation:   new entry at index 0 on valid fault transition (PUB002)    │
 * │ History[0..4]   │ Shift:        older entries shift toward higher indices (PUB002)          │
 * │                 │ Retention:    five most recent; older beyond index 4 are discarded       │
 * │                 │ Reset:        power-up zeros all five entries (PUB005)                   │
 * └─────────────────┴───────────────────────────────────────────────────────────────────────────┘
 * 
 * ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
 * │ TIMING BOUNDARY (PUB001)                                                                    │
 * │ - 500 ms hold: TON.Q = elapsed >= PT; first satisfying tick = ceil(500ms/1ms) = 500 ticks  │
 * │ - Timer reset before restart ensures deterministic restart behavior                        │
 * └─────────────────────────────────────────────────────────────────────────────────────────────┘
 *
 * CONTRACT_RULES [{"kind": "hold_until_reset", "output": "THICKNESS_ALARM", "set_input": "THICKNESS_FAULT", "reset_input": null}]
 *)

(* Detect rising edge of fault while signal is valid *)
faultRising(CLK := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID AND NOT prevFault);

(* Detect falling edge of VALID to clear state *)
validFalling(CLK := prevValid AND NOT THICKNESS_SIGNAL_VALID);

(* Handle signal invalidation: clear latch, alarm, and timer *)
IF validFalling.Q THEN
    latch := FALSE;
    inHoldPhase := FALSE;
    holdTimer(IN := FALSE, PT := T#500ms);
    THICKNESS_ALARM := FALSE;
END_IF;

(* When VALID is FALSE, ensure alarm and timer are cleared *)
IF NOT THICKNESS_SIGNAL_VALID THEN
    latch := FALSE;
    inHoldPhase := FALSE;
    holdTimer(IN := FALSE, PT := T#500ms);
    THICKNESS_ALARM := FALSE;
END_IF;

(* Process fault: activate alarm and record history *)
IF faultRising.Q THEN
    Slab_Fault_Counter := Slab_Fault_Counter + 1;
    
    FOR tmpI := 4 TO 1 BY -1 DO
        Slab_Fault_History[tmpI] := Slab_Fault_History[tmpI - 1];
    END_FOR;
    
    Slab_Fault_History[0] := FaultTimestamp;
    
    latch := TRUE;
    inHoldPhase := TRUE;
    holdTimer(IN := FALSE, PT := T#500ms);
    holdTimer(IN := TRUE, PT := T#500ms);
    THICKNESS_ALARM := TRUE;
END_IF;

(* Alarm follows latch during hold phase, then follows fault *)
IF latch THEN
    IF inHoldPhase THEN
        THICKNESS_ALARM := TRUE;
    ELSE
        THICKNESS_ALARM := THICKNESS_FAULT;
    END_IF;
ELSE
    THICKNESS_ALARM := FALSE;
END_IF;

(* Update hold phase and timer *)
IF inHoldPhase THEN
    IF holdTimer.Q THEN
        inHoldPhase := FALSE;
        IF NOT THICKNESS_FAULT THEN
            latch := FALSE;
        END_IF;
    END_IF;
END_IF;

(* Accumulate runtime while cutting normally *)
IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TO_LTIME(CycleTime);
END_IF;

(* Update previous state for edge detection *)
prevFault := THICKNESS_FAULT;
prevValid := THICKNESS_SIGNAL_VALID;

END_FUNCTION_BLOCK