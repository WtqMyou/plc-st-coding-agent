FUNCTION_BLOCK Weld_Gap_Alarm
(* ENGINEERING_CONTRACT
 * States: INIT(5s inhibit) | MONITOR(gap OK) | ALARM(gap debounced)
 * 
 * Operator_Alert: FALSE during INIT, TRUE only when gap TRUE for >= DebounceTime
 * Weld_Soft_Start_Active: TRUE during INIT (PUB005), FALSE otherwise
 * 
 * Reset/priority: E_Stop FALSE (active) >> INIT >> MONITOR/ALARM
 * - E_Stop: clears alarm, timers (PUB004)
 * - Gap FALSE: clears alarm, debounce timer (PUB003)
 * - No latching; alarm is level-driven by debounced gap
 *)
VAR_INPUT
    Gap_Exceeded   : BOOL;
    Weld_E_Stop_NC : BOOL;
    DebounceTime   : TIME;
END_VAR

VAR_OUTPUT
    Operator_Alert         : BOOL := FALSE;
    Weld_Soft_Start_Active : BOOL := TRUE;
END_VAR

VAR
    init_timer     : TON;
    debounce_timer : TON;
    init_complete  : BOOL := FALSE;
END_VAR

    // E-Stop priority: active when Weld_E_Stop_NC = FALSE
    IF NOT Weld_E_Stop_NC THEN
        Operator_Alert         := FALSE;
        Weld_Soft_Start_Active := FALSE;
        debounce_timer(IN := FALSE);
        init_timer(IN := FALSE);
        init_complete := FALSE;
        RETURN;
    END_IF;

    // Initialization: 5-second power-up inhibition (PUB002, PUB005)
    IF NOT init_complete THEN
        init_timer(IN := NOT init_complete, PT := T#5S);
        Weld_Soft_Start_Active := TRUE;
        Operator_Alert         := FALSE;
        debounce_timer(IN := FALSE);

        IF init_timer.Q THEN
            init_complete          := TRUE;
            Weld_Soft_Start_Active := FALSE;
        END_IF;

    // Normal monitoring: debounce gap signal (PUB003)
    ELSE
        Operator_Alert := FALSE;

        IF Gap_Exceeded THEN
            debounce_timer(IN := TRUE, PT := DebounceTime);
            Operator_Alert := debounce_timer.Q;
        ELSE
            debounce_timer(IN := FALSE);
        END_IF;
    END_IF;

END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)