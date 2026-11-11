FUNCTION_BLOCK WeldGapAlarm
VAR_INPUT
    Gap_Exceeded    : BOOL;      // Scanner indication that the gap exceeds 1.5 mm
    Weld_E_Stop_NC  : BOOL;      // TRUE = inactive, FALSE = active (emergency stop)
    DebounceTime    : TIME;      // Gap-signal debounce duration during normal monitoring
END_VAR

VAR_OUTPUT
    Operator_Alert         : BOOL;  // Audible and visual alarm command
    Weld_Soft_Start_Active : BOOL;  // Monitoring-inhibition status during 5-second power-up initialization
END_VAR

VAR
    InitTimer    : TON;          // 5-second initialization inhibition timer
    DebounceTmr  : TON;          // Gap signal debounce timer during normal monitoring
    bInitDone    : BOOL;         // Power-up initialization completion flag
END_VAR

    // E-Stop takes highest priority over initialization and normal monitoring
    IF NOT Weld_E_Stop_NC THEN
        Operator_Alert         := FALSE;
        Weld_Soft_Start_Active := FALSE;
        DebounceTmr(IN := FALSE);
        InitTimer(IN := FALSE);
        bInitDone := FALSE;
        RETURN;
    END_IF

    // 5-second initialization inhibition period
    IF NOT bInitDone THEN
        Weld_Soft_Start_Active := TRUE;
        Operator_Alert         := FALSE;
        InitTimer(IN := TRUE, PT := T#5S);
        
        IF InitTimer.Q THEN
            bInitDone := TRUE;
            InitTimer(IN := FALSE);
        END_IF;
        
        // During initialization, debounce time does NOT accumulate
        RETURN;
    END_IF;

    // Normal gap monitoring after initialization
    Weld_Soft_Start_Active := FALSE;
    
    // Debounce logic: alarm only after Gap_Exceeded remains TRUE for DebounceTime
    IF Gap_Exceeded THEN
        DebounceTmr(IN := TRUE, PT := DebounceTime);
        Operator_Alert := DebounceTmr.Q;
    ELSE
        DebounceTmr(IN := FALSE);
        Operator_Alert := FALSE;
    END_IF;

END_FUNCTION_BLOCK