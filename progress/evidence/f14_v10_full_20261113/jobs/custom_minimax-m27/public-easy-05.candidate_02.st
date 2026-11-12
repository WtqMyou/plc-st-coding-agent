(* ENGINEERING_CONTRACT
 * ==================================================================
 * State Machine: 2-state (INIT/MONITORING) with E-Stop priority
 * 
 * | Output          | Activation          | Retention          | Reset/Deactivation              | Scan Priority |
 * |-----------------|---------------------|--------------------|----------------------------------|---------------|
 * | Operator_Alert  | Gap_Exceed TRUE for | Latch until gap    | Gap_Exceed FALSE (immediate),    | E-Stop highest|
 * |                 | DebounceTime        | stays TRUE         | E-Stop active (immediate)        |               |
 * | Weld_Soft_Start | TRUE during INIT    | Hold across scans  | Timer.Q TRUE → MONITORING entry  | After E-Stop  |
 * |                 |                     |                    | (immediate deactivation)         |               |
 * 
 * Boundary/Units:
 * - INIT duration: T#5s (fixed, not configurable)
 * - DebounceTime: input TIME, must be positive during MONITORING
 * - Timer.ET saturates at PT (IEC 61131-3 TON standard)
 * 
 * E-Stop Priority (PUB005): checked first every scan, overrides all
 * ==================================================================
 *)

(* CONTRACT_RULES
 * [
 *   {
 *     "kind": "hold_until_reset",
 *     "output": "Weld_Soft_Start_Active",
 *     "set_input": null,
 *     "reset_input": "SoftStartTimer.Q"
 *   }
 * ]
 *)

FUNCTION_BLOCK Weld_Gap_Alarm
VAR_INPUT
    Gap_Exceeded    : BOOL;
    Weld_E_Stop_NC  : BOOL;
    DebounceTime    : TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert        : BOOL := FALSE;
    Weld_Soft_Start_Active : BOOL := FALSE;
END_VAR
VAR
    State            : UINT := 0;  (* 0=INIT, 1=MONITORING *)
    SoftStartTimer   : TON;
    AlarmTimer       : TON;
END_VAR

    (* E-STOP PRIORITY (PUB005): Highest priority, checked every scan *)
    IF NOT Weld_E_Stop_NC THEN
        Operator_Alert         := FALSE;
        AlarmTimer(IN := FALSE, PT := DebounceTime);
        Weld_Soft_Start_Active  := FALSE;
        State                  := 0;
        SoftStartTimer(IN := FALSE, PT := T#5s);
        RETURN;
    END_IF;

    (* STATE MACHINE *)
    IF State = 0 THEN
        (* INIT: 5-second power-up inhibition (PUB002) *)
        SoftStartTimer(IN := TRUE, PT := T#5s);
        Operator_Alert         := FALSE;
        Weld_Soft_Start_Active  := TRUE;
        AlarmTimer(IN := FALSE, PT := DebounceTime);

        (* Transition to MONITORING after 5 seconds (PUB002) *)
        IF SoftStartTimer.Q THEN
            State := 1;
        END_IF;

    ELSE  (* State = 1: MONITORING (PUB003, PUB004) *)
        SoftStartTimer(IN := FALSE, PT := T#5s);
        Weld_Soft_Start_Active  := FALSE;

        (* Debounce gap signal during monitoring *)
        AlarmTimer(IN := Gap_Exceeded, PT := DebounceTime);

        (* Alarm when gap exceeded for full DebounceTime *)
        Operator_Alert   := AlarmTimer.Q;
    END_IF;

END_FUNCTION_BLOCK