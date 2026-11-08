FUNCTION_BLOCK FB
VAR_INPUT
    THICKNESS_FAULT        : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN            : BOOL;
    FaultTimestamp         : DINT;
    CycleTime              : TIME;
END_VAR
VAR_OUTPUT
    THICKNESS_ALARM            : BOOL;
    Slab_Fault_Counter         : UINT;
    Slab_Runtime_Accumulator   : LINT;
    Slab_Fault_History         : ARRAY[0..4] OF DINT;
END_VAR
VAR
    FaultPrev       : BOOL := FALSE;
    AlarmHoldTimer  : TON;
END_VAR

(* Alarm control *)
IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM      := FALSE;
    AlarmHoldTimer(IN := FALSE);
ELSE
    (* Rising edge of a valid fault *)
    IF THICKNESS_FAULT AND NOT FaultPrev THEN
        (* Increment fault counter *)
        Slab_Fault_Counter := Slab_Fault_Counter + 1;

        (* Shift history and store newest timestamp at index 0 *)
        Slab_Fault_History[4] := Slab_Fault_History[3];
        Slab_Fault_History[3] := Slab_Fault_History[2];
        Slab_Fault_History[2] := Slab_Fault_History[1];
        Slab_Fault_History[1] := Slab_Fault_History[0];
        Slab_Fault_History[0] := FaultTimestamp;

        (* Start 500 ms hold timer *)
        AlarmHoldTimer(IN := TRUE, PT := T#500ms);

        (* Activate alarm immediately *)
        THICKNESS_ALARM := TRUE;
    ELSE
        (* Normal alarm state handling *)
        IF THICKNESS_FAULT THEN
            (* Fault still present – keep alarm active *)
            THICKNESS_ALARM      := TRUE;
            AlarmHoldTimer(IN := TRUE, PT := T#500ms);
        ELSE
            (* Fault cleared – apply minimum hold period *)
            IF AlarmHoldTimer.Q THEN
                (* Hold time elapsed – deactivate alarm *)
                THICKNESS_ALARM      := FALSE;
                AlarmHoldTimer(IN := FALSE);
            ELSE
                (* Still within hold period *)
                THICKNESS_ALARM      := TRUE;
                AlarmHoldTimer(IN := TRUE, PT := T#500ms);
            END_IF
        END_IF
    END_IF
END_IF

(* Update edge detection variable *)
FaultPrev := THICKNESS_FAULT;

(* Runtime accumulation (only when signal valid, cutting running and no fault) *)
IF THICKNESS_SIGNAL_VALID AND CUTTING_RUN AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + (CycleTime / T#1ms);
END_IF

END_FUNCTION_BLOCK