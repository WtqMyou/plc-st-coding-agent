(* ENGINEERING_CONTRACT *)
(*
| Output/State            | Activation              | Retention          | Reset/Deactivation                | Same-scan Priority | Units/Boundaries     |
|-------------------------|-------------------------|--------------------|-----------------------------------|--------------------|----------------------|
| THICKNESS_ALARM         | Immediate on valid TRUE | Hold >=500ms min   | Signal invalid OR hold timer done | Alarm active wins  | TON PT=500ms         |
| Slab_Fault_Counter      | Rising edge of valid    | Count accumulates  | Power-up only                     | N/A                | UINT max             |
| Slab_Fault_History[0]   | Rising edge of valid    | Newest entry       | Power-up only                     | N/A                | DINT timestamp       |
| Slab_Fault_History[1-4] | Shifted from lower idx  | Older entries      | Power-up only                     | N/A                | DINT timestamp       |
| Slab_Runtime_Accumulator| Accum when cutting valid| Accumulates       | Power-up only                     | N/A                | LTIME nanoseconds    |
| Hold timer (TON)        | Starts on fault clear   | Runs for PT        | Q=TRUE stops hold; signal invalid | N/A                | PT=T#500ms           |
| prev_valid_fault (VAR)  | Updated each scan       | Last cycle fault   | Power-up only                     | N/A                | BOOL                 |
| alarm_state (VAR)       | Transitions per FSM     | Holds across scans | Signal invalid resets             | N/A                | (0,1,2) enum         |
*)
(* CONTRACT_RULES [] *)

TYPE AlarmState :
(
    AlarmOff    := 0,
    FaultActive := 1,
    FaultCleared := 2
);
END_TYPE;

FUNCTION_BLOCK SlabThicknessMonitor
    VAR_INPUT
        THICKNESS_FAULT        : BOOL;
        THICKNESS_SIGNAL_VALID : BOOL;
        CUTTING_RUN            : BOOL;
        FaultTimestamp         : DINT;
        CycleTime              : TIME;
    END_VAR
    VAR_OUTPUT
        THICKNESS_ALARM         : BOOL := FALSE;
        Slab_Fault_Counter      : UINT := 0;
        Slab_Runtime_Accumulator: LTIME := LTIME#0s;
        Slab_Fault_History      : ARRAY[0..4] OF DINT := [5(DINT#0)];
    END_VAR
    VAR
        prev_valid_fault : BOOL := FALSE;
        hold_timer       : TON;
        alarm_state      : AlarmState := AlarmOff;
        tmp_hold_q       : BOOL;
    END_VAR

    // Clear all state when signal becomes invalid (power-up also covered by first-scan initialization)
    IF NOT THICKNESS_SIGNAL_VALID THEN
        alarm_state         := AlarmOff;
        THICKNESS_ALARM     := FALSE;
        hold_timer(IN := FALSE);
        prev_valid_fault    := FALSE;
        Slab_Fault_Counter  := 0;
        Slab_Fault_History  := [5(DINT#0)];
        Slab_Runtime_Accumulator := LTIME#0s;
    ELSE
        // Detect FALSE-to-TRUE transition of valid fault signal (PUB001)
        IF prev_valid_fault = FALSE AND THICKNESS_FAULT = TRUE THEN
            // Shift history: older entries toward higher indices, retain 5 most recent
            Slab_Fault_History[4] := Slab_Fault_History[3];
            Slab_Fault_History[3] := Slab_Fault_History[2];
            Slab_Fault_History[2] := Slab_Fault_History[1];
            Slab_Fault_History[1] := Slab_Fault_History[0];
            Slab_Fault_History[0] := FaultTimestamp;
            Slab_Fault_Counter := Slab_Fault_Counter + UINT#1;
        END_IF;

        // Accumulate runtime only while cutting, signal valid, no fault (PUB003)
        IF CUTTING_RUN AND NOT THICKNESS_FAULT THEN
            Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + CycleTime;
        END_IF;

        // Alarm state machine with 500ms minimum hold (PUB001, PUB002)
        // Evaluate timer first so same-scan enable and elapsed origin agree
        hold_timer(IN := (alarm_state = FaultCleared));
        tmp_hold_q := hold_timer.Q;

        CASE alarm_state OF
            AlarmOff:
                IF THICKNESS_FAULT THEN
                    alarm_state     := FaultActive;
                    THICKNESS_ALARM := TRUE;
                END_IF;

            FaultActive:
                THICKNESS_ALARM := TRUE;
                IF NOT THICKNESS_FAULT THEN
                    alarm_state := FaultCleared;
                END_IF;

            FaultCleared:
                THICKNESS_ALARM := TRUE;
                IF tmp_hold_q THEN
                    alarm_state     := AlarmOff;
                    THICKNESS_ALARM := FALSE;
                END_IF;
        END_CASE;
    END_IF;

    // Update previous fault state for next scan edge detection
    prev_valid_fault := THICKNESS_FAULT;
END_FUNCTION_BLOCK