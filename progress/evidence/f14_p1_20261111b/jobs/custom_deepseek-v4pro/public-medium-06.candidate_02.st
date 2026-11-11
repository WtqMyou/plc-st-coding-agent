FUNCTION_BLOCK SlabThicknessAlarmFaultHistory
VAR_INPUT
    THICKNESS_FAULT : BOOL;               (* Thickness deviation exceeds the permitted tolerance *)
    THICKNESS_SIGNAL_VALID : BOOL;        (* Thickness-signal validity; FALSE means signal lost/unavailable *)
    CUTTING_RUN : BOOL;                   (* Actual cutting-equipment running status *)
    FaultTimestamp : DINT;                (* Current timestamp in seconds, used as fault-record identifier *)
    CycleTime : TIME;                     (* Actual elapsed interval represented by this invocation; must be positive *)
END_VAR
VAR_OUTPUT
    THICKNESS_ALARM : BOOL;               (* Thickness alarm with a minimum 500 ms hold duration *)
    Slab_Fault_Counter : UINT;            (* Number of valid thickness-fault occurrences *)
    Slab_Runtime_Accumulator : LTIME;     (* Accumulated normal-cutting runtime *)
    Slab_Fault_History : ARRAY[0..4] OF DINT; (* Five most recent fault timestamps; index 0 is newest; read-only to callers *)
END_VAR
VAR
    AlarmHoldActive : BOOL := FALSE;      (* Internal flag: minimum alarm hold in progress *)
    AlarmHoldElapsed : TIME := T#0ms;     (* Elapsed time within the current hold period *)
    LastValidFault : BOOL := FALSE;       (* Last valid fault state for edge detection *)
    InitDone : BOOL := FALSE;             (* Power-up initialization flag *)
    i : INT;                              (* Loop index *)
END_VAR

    (* ----- Power-up initialization ----- *)
    IF NOT InitDone THEN
        THICKNESS_ALARM := FALSE;
        Slab_Fault_Counter := 0;
        Slab_Runtime_Accumulator := LTIME#0s;
        FOR i := 0 TO 4 DO
            Slab_Fault_History[i] := 0;
        END_FOR;
        AlarmHoldActive := FALSE;
        AlarmHoldElapsed := T#0ms;
        LastValidFault := FALSE;
        InitDone := TRUE;
    END_IF;

    (* ----- Main logic ----- *)
    IF NOT THICKNESS_SIGNAL_VALID THEN
        (* Signal lost/unavailable: switch off alarm, clear holding state, no recording/accumulation *)
        THICKNESS_ALARM := FALSE;
        AlarmHoldActive := FALSE;
        AlarmHoldElapsed := T#0ms;
        LastValidFault := FALSE;  (* Reset edge detection so a valid fault after signal recovery counts as a new occurrence *)
    ELSE
        (* Signal valid: process fault detection, alarm hold, edge counting, history, and runtime accumulation *)

        (* Rising edge of valid fault signal *)
        IF (THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID) AND NOT LastValidFault THEN
            (* Increment fault counter *)
            Slab_Fault_Counter := Slab_Fault_Counter + 1;

            (* Update history: shift older entries to higher indices, store newest at index 0 *)
            Slab_Fault_History[4] := Slab_Fault_History[3];
            Slab_Fault_History[3] := Slab_Fault_History[2];
            Slab_Fault_History[2] := Slab_Fault_History[1];
            Slab_Fault_History[1] := Slab_Fault_History[0];
            Slab_Fault_History[0] := FaultTimestamp;

            (* Start/restart minimum 500 ms hold timer *)
            AlarmHoldActive := TRUE;
            AlarmHoldElapsed := T#0ms;
        END_IF;

        (* Update minimum hold timer *)
        IF AlarmHoldActive THEN
            AlarmHoldElapsed := AlarmHoldElapsed + CycleTime;
            IF AlarmHoldElapsed >= T#500ms THEN
                AlarmHoldActive := FALSE;   (* Minimum hold period expired *)
                AlarmHoldElapsed := T#0ms;  (* Reset for future use *)
            END_IF;
        END_IF;

        (* Alarm output: active while fault persists OR during the minimum hold period *)
        THICKNESS_ALARM := (THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID) OR AlarmHoldActive;

        (* Accumulate normal-cutting runtime only when cutting, signal valid, and no fault *)
        IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
            Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LTIME(CycleTime);
        END_IF;

        (* Remember current valid fault state for next edge detection *)
        LastValidFault := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID;
    END_IF;

END_FUNCTION_BLOCK