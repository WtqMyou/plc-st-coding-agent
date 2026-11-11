(* Slab Thickness Alarm and Fault History Monitor
 * Requirements:
 * 1. Alarm with 500ms minimum hold, active while fault persists
 * 2. Fault counter and 5-entry history (shift register, newest at index 0)
 * 3. Runtime accumulation during normal cutting (valid signal, no fault)
 * 4. Clear state when signal invalid or at power-up
 * 5. Statistics/history are read-only to external callers
 *)
PROGRAM SlabThicknessMonitor
VAR
    (* === Inputs === *)
    THICKNESS_FAULT        : BOOL;   (* Thickness deviation exceeds tolerance *)
    THICKNESS_SIGNAL_VALID : BOOL;   (* Thickness signal validity *)
    CUTTING_RUN            : BOOL;   (* Cutting equipment running status *)
    FaultTimestamp         : DINT;   (* Current timestamp in seconds *)
    CycleTime              : TIME;   (* Elapsed interval for this invocation *)
    
    (* === Outputs === *)
    THICKNESS_ALARM           : BOOL;                    (* Alarm with min 500ms hold *)
    Slab_Fault_Counter        : UINT;                    (* Valid fault occurrence count *)
    Slab_Runtime_Accumulator  : LTIME;                   (* Accumulated normal runtime *)
    Slab_Fault_History        : ARRAY[0..4] OF DINT;     (* 5 recent fault timestamps *)
    
    (* === Internal State === *)
    AlarmHoldTimer   : TON;     (* Timer for 500ms alarm hold *)
    FaultWasActive   : BOOL;    (* Rising-edge detection for fault signal *)
    PowerUpComplete  : BOOL;    (* Power-up initialization flag *)
    i                : INT;     (* Loop index for history shift *)
END_VAR

(* === Power-Up Initialization === *)
IF NOT PowerUpComplete THEN
    THICKNESS_ALARM            := FALSE;
    Slab_Fault_Counter         := 0;
    Slab_Runtime_Accumulator   := LTIME#0s;
    
    FOR i := 0 TO 4 DO
        Slab_Fault_History[i] := 0;
    END_FOR
    
    FaultWasActive  := FALSE;
    PowerUpComplete := TRUE;
END_IF

(* === Clear State When Signal Invalid === *)
IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM  := FALSE;
    AlarmHoldTimer(IN := FALSE);
    FaultWasActive   := FALSE;
ELSE
    (* === Alarm Logic: Immediate activation + 500ms hold === *)
    AlarmHoldTimer(IN  := THICKNESS_FAULT,
                   PT  := T#500ms);
    THICKNESS_ALARM := THICKNESS_FAULT OR AlarmHoldTimer.Q;
    
    (* === Fault History: Rising-edge detection + shift register === *)
    IF THICKNESS_FAULT AND NOT FaultWasActive THEN
        Slab_Fault_Counter         := Slab_Fault_Counter + 1;
        Slab_Fault_History[4]      := Slab_Fault_History[3];
        Slab_Fault_History[3]      := Slab_Fault_History[2];
        Slab_Fault_History[2]      := Slab_Fault_History[1];
        Slab_Fault_History[1]      := Slab_Fault_History[0];
        Slab_Fault_History[0]      := FaultTimestamp;
    END_IF;
    
    (* Update fault state for next scan *)
    FaultWasActive := THICKNESS_FAULT;
    
    (* === Runtime Accumulation: Normal cutting only === *)
    IF CUTTING_RUN AND NOT THICKNESS_FAULT THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + CycleTime;
    END_IF
END_IF

END_PROGRAM