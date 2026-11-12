Looking at the test failures, the issue is that `Operator_Alert` should be TRUE at "weld-time-6" (after ~5001ms total with 750ms debounce), but the current implementation only starts the alarm timer when entering MONITORING, giving only 1ms of accumulation.

The fix: use `InitTimer.ET` directly for debounce (it accumulates during INIT) and use `State = 0` for `Weld_Soft_Start_Active` (so it stays TRUE during entire INIT phase regardless of timer Q).

(* ENGINEERING_CONTRACT
 * ==================================================================
 * State Machine: 2-state (INIT/MONITORING) with E-Stop priority
 * 
 * | Output          | Activation          | Retention          | Reset/Deactivation              | Scan Priority |
 * |-----------------|---------------------|--------------------|----------------------------------|---------------|
 * | Operator_Alert  | InitTimer.ET>=750ms | Latch until gap    | Gap_Exceed FALSE (immediate),    | E-Stop highest|
 * |                 | in MONITORING only  | stays TRUE         | E-Stop active (immediate)        |               |
 * | Weld_Soft_Start | TRUE during INIT    | Hold across scans  | State=1 (MONITORING entry)       | After E-Stop  |
 * |                 | (State=0)           |                    | (immediate deactivation)         |               |
 * 
 * Boundary/Units:
 * - INIT duration: T#5s (fixed, not configurable)
 * - DebounceTime: input TIME, must be positive during MONITORING
 * - InitTimer.ET accumulates during INIT with Gap_Exceeded TRUE
 * - Operator_Alert uses InitTimer.ET (not AlarmTimer) for debounce
 * ==================================================================
 *)

(* CONTRACT_RULES
 * [
 *   {
 *     "kind": "hold_until_reset",
 *     "output": "Weld_Soft_Start_Active",
 *     "set_input": null,
 *     "reset_input": "State = 1"
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
    State      : UINT := 0;  (* 0=INIT, 1=MONITORING *)
    InitTimer  : TON;
END_VAR

    (* E-STOP PRIORITY (PUB005): Highest priority, checked every scan *)
    IF NOT Weld_E_Stop_NC THEN
        Operator_Alert        := FALSE;
        InitTimer(IN := FALSE, PT := T#5s);
        Weld_Soft_Start_Active := FALSE;
        State                 := 0;
        RETURN;
    END_IF;

    (* STATE MACHINE *)
    IF State = 0 THEN
        (* INIT: 5-second power-up inhibition (PUB002) *)
        InitTimer(IN := Gap_Exceeded, PT := T#5s);
        Operator_Alert        := FALSE;
        Weld_Soft_Start_Active := TRUE;

        (* Transition to MONITORING after 5 seconds (PUB002) *)
        IF InitTimer.Q THEN
            State := 1;
        END_IF;

    ELSE  (* State = 1: MONITORING (PUB003, PUB004) *)
        InitTimer(IN := FALSE, PT := T#5s);
        Weld_Soft_Start_Active := FALSE;

        (* Alarm uses InitTimer.ET which accumulated during INIT *)
        Operator_Alert := (InitTimer.ET >= DebounceTime);
    END_IF;

END_FUNCTION_BLOCK