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
    state : UINT := 0;
END_VAR

IF NOT Weld_E_Stop_NC THEN
    Operator_Alert := FALSE;
    Weld_Soft_Start_Active := FALSE;
    state := 0;
    initTimer(IN := FALSE);
    debounceTimer(IN := FALSE);
    initTimer();
    debounceTimer();
    RETURN;
END_IF;

IF state = 0 THEN
    initTimer(IN := TRUE, PT := T#5S);
    initTimer();
    Operator_Alert := FALSE;
    Weld_Soft_Start_Active := TRUE;
    
    IF initTimer.Q THEN
        state := 1;
        initTimer(IN := FALSE);
        debounceTimer(IN := FALSE);
        initTimer();
        debounceTimer();
    END_IF;
    RETURN;
END_IF;

IF state = 1 THEN
    Weld_Soft_Start_Active := FALSE;
    
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
END_IF;

END_FUNCTION_BLOCK