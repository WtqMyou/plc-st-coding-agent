FUNCTION_BLOCK FB_SlabThicknessMonitor
(* 
 * ENGINEERING_CONTRACT
 * =============================================================================
 * Output/State          | Activation          | Retention            | Reset/Deactivation            | Units
 * ----------------------+---------------------+----------------------+-------------------------------+-----------------
 * THICKNESS_ALARM       | Rising edge valid   | Min 500ms hold;      | Signal invalid clears all     | BOOL
 *                       | THICKNESS_FAULT     | continues if fault   | alarm and hold state (PUB001) |
 * Alarm hold timer      | TON(IN: valid &     | TON.ET saturates at  | Signal invalid resets TON     | LTIME (≥500ms)
 *                       |   (fault OR holding))| PT=500ms            |                               |
 * Holding flag          | Fault OR holding    | Self-holds while     | Signal invalid clears         | BOOL
 *                       |                     |   fault OR timer run |                               |
 * Slab_Fault_Counter    | FALSE→TRUE valid    | Accumulates monoton  | None by task spec             | UINT
 *                       | fault transition    | (never auto-reset)   |                               |
 * Slab_Fault_History[0] | New fault entry     | Shifts [n]→[n+1]     | Power-up init to 0            | ARRAY[0..4] DINT
 *                       | writes to index 0   | (0 newest)           |                               |
 * Slab_Runtime_Accumulator| While CUTTING_RUN  | Preserved when       | None by task spec             | LTIME (accumulates)
 *                       | + valid + no fault  | conditions not met   |                               |
 * =============================================================================
 * CONTRACT_RULES [{"kind": "hold_until_reset", "output": "THICKNESS_ALARM", "set_input": "THICKNESS_FAULT", "reset_input": null}]
 *)

VAR_INPUT
    THICKNESS_FAULT        : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN            : BOOL;
    FaultTimestamp         : DINT;
    CycleTime              : TIME;
END_VAR

VAR_OUTPUT
    THICKNESS_ALARM           : BOOL;
    Slab_Fault_Counter        : UINT;
    Slab_Runtime_Accumulator  : LTIME;
    Slab_Fault_History        : ARRAY[0..4] OF DINT;
END_VAR

VAR
    faultRisingEdge    : R_TRIG;
    signalValidPrev    : BOOL;
    alarmHoldTimer     : TON;
    alarmHolding       : BOOL;
    faultActive        : BOOL;
END_VAR

// ---------------------------------------------------------------------------
// Power-up initialization (first scan after instantiation)
// ---------------------------------------------------------------------------
IF NOT alarmHoldTimer.Q AND NOT faultActive AND NOT alarmHolding THEN
    Slab_Fault_Counter       := 0;
    Slab_Runtime_Accumulator := LTIME#0;
    Slab_Fault_History[0]    := 0;
    Slab_Fault_History[1]    := 0;
    Slab_Fault_History[2]    := 0;
    Slab_Fault_History[3]    := 0;
    Slab_Fault_History[4]    := 0;
END_IF;

// ---------------------------------------------------------------------------
// Detect FALSE→TRUE transition on valid fault signal
// ---------------------------------------------------------------------------
faultRisingEdge(CLK := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID);

// ---------------------------------------------------------------------------
// Handle signal-valid transitions: clear alarm/hold when signal lost (PUB001)
// ---------------------------------------------------------------------------
IF THICKNESS_SIGNAL_VALID THEN
    IF NOT signalValidPrev THEN
        // Signal just restored after being invalid
        alarmHolding  := FALSE;
        alarmHoldTimer(IN := FALSE);
        faultActive   := FALSE;
    END_IF;

    // -------------------------------------------------------------------------
    // On rising edge of valid fault: record entry and start hold
    // -------------------------------------------------------------------------
    IF faultRisingEdge.Q THEN
        // Increment counter
        Slab_Fault_Counter := Slab_Fault_Counter + UINT#1;

        // Shift history: index 3→4, 2→3, 1→2, 0→1, then write new to 0
        Slab_Fault_History[4] := Slab_Fault_History[3];
        Slab_Fault_History[3] := Slab_Fault_History[2];
        Slab_Fault_History[2] := Slab_Fault_History[1];
        Slab_Fault_History[1] := Slab_Fault_History[0];
        Slab_Fault_History[0] := FaultTimestamp;

        // Activate alarm and start 500 ms hold timer
        faultActive        := TRUE;
        alarmHolding       := TRUE;
        alarmHoldTimer(IN  := TRUE, PT := T#500ms);
    END_IF;

    // -------------------------------------------------------------------------
    // Update alarm state: hold while fault persists or timer running
    // -------------------------------------------------------------------------
    IF faultActive THEN
        // Keep timer running while fault is present
        alarmHoldTimer(IN := TRUE, PT := T#500ms);

        // Alarm stays active while fault or hold timer active
        alarmHolding := THICKNESS_FAULT OR alarmHoldTimer.Q;

        // Release hold tracking once fault clears and timer completes
        IF NOT THICKNESS_FAULT AND alarmHolding AND NOT alarmHoldTimer.Q THEN
            alarmHolding := FALSE;
        END_IF;

        // Clear fault-active flag when fault goes away (hold may continue)
        IF NOT THICKNESS_FAULT THEN
            faultActive := FALSE;
        END_IF;
    END_IF;

    // Final alarm output
    THICKNESS_ALARM := alarmHolding OR faultActive;

    // -------------------------------------------------------------------------
    // Runtime accumulation: only while cutting, signal valid, no fault
    // -------------------------------------------------------------------------
    IF CUTTING_RUN AND NOT THICKNESS_FAULT THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TO_LTIME(CycleTime);
    END_IF;

ELSE
    // Signal invalid: clear alarm and all hold state (PUB001)
    THICKNESS_ALARM  := FALSE;
    alarmHolding     := FALSE;
    faultActive      := FALSE;
    alarmHoldTimer(IN := FALSE);
END_IF;

// ---------------------------------------------------------------------------
// Latch previous scan signal-valid state for edge detection
// ---------------------------------------------------------------------------
signalValidPrev := THICKNESS_SIGNAL_VALID;

END_FUNCTION_BLOCK