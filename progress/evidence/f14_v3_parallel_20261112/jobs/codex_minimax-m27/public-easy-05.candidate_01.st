FUNCTION_BLOCK WeldGapAlarm
VAR_INPUT
    Gap_Exceeded : BOOL;
    Weld_E_Stop_NC : BOOL;
    DebounceTime : TIME;
END_VAR

VAR_OUTPUT
    Operator_Alert : BOOL := FALSE;
    Weld_Soft_Start_Active : BOOL := TRUE;
END_VAR

VAR
    initTimer : TON;
    debounceTimer : TON;
    monitoringActive : BOOL := FALSE;
END_VAR

// E-Stop takes priority over all states
IF NOT Weld_E_Stop_NC THEN
    Operator_Alert := FALSE;
    Weld_Soft_Start_Active := FALSE;
    monitoringActive := FALSE;
    
    // Reset timers when E-Stop is active
    initTimer(IN := FALSE);
    debounceTimer(IN := FALSE);
    initTimer();
    debounceTimer();
    RETURN;
END_IF;

// Initialization phase: 5-second power-up inhibition
IF NOT monitoringActive THEN
    initTimer(IN := TRUE, PT := T#5S);
    initTimer();
    
    Operator_Alert := FALSE;
    Weld_Soft_Start_Active := TRUE;
    
    IF initTimer.Q THEN
        monitoringActive := TRUE;
        Weld_Soft_Start_Active := FALSE;
        
        // Reset timers upon entering monitoring
        initTimer(IN := FALSE);
        debounceTimer(IN := FALSE);
        initTimer();
        debounceTimer();
    END_IF;
    
    initTimer(IN := FALSE);
    initTimer();
    RETURN;
END_IF;

// Normal gap monitoring with debounce
IF NOT Gap_Exceeded THEN
    Operator_Alert := FALSE;
    debounceTimer(IN := FALSE);
    debounceTimer();
ELSE
    debounceTimer(IN := TRUE, PT := DebounceTime);
    debounceTimer();
    
    IF debounceTimer.Q THEN
        Operator_Alert := TRUE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK