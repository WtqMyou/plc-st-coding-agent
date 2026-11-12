TYPE GapAlarmState :
(
    EStop  := 0,
    Init   := 1,
    Monitor := 2
) END_TYPE

FUNCTION_BLOCK Weld_Gap_Alarm
VAR_INPUT
    Gap_Exceeded   : BOOL;
    Weld_E_Stop_NC : BOOL;
    DebounceTime   : TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert        : BOOL := FALSE;
    Weld_Soft_Start_Active: BOOL := FALSE;
END_VAR
VAR
    State        : GapAlarmState := Init;
    Init_Timer   : TON;
    Gap_Debounce : TON;
END_VAR

// EStop has highest priority
IF NOT Weld_E_Stop_NC THEN
    Operator_Alert        := FALSE;
    Weld_Soft_Start_Active := FALSE;
    Init_Timer(IN := FALSE);
    Gap_Debounce(IN := FALSE);
    State := EStop;
    RETURN;
END_IF;

// EStop released - transition to initialization
IF State = EStop THEN
    State := Init;
END_IF;

CASE State OF
    Init:
        Init_Timer(IN := TRUE, PT := T#5s);
        Weld_Soft_Start_Active := TRUE;
        Operator_Alert := FALSE;
        Gap_Debounce(IN := FALSE);
        
        IF Init_Timer.Q THEN
            State := Monitor;
            Weld_Soft_Start_Active := FALSE;
        END_IF;
    
    Monitor:
        Init_Timer(IN := FALSE);
        Weld_Soft_Start_Active := FALSE;
        
        // Debounce gap signal: timer accumulates while TRUE,
        // resets when FALSE (ET tracks elapsed time)
        Gap_Debounce(IN := Gap_Exceeded, PT := DebounceTime);
        
        IF Gap_Debounce.Q THEN
            Operator_Alert := TRUE;
        ELSE
            Operator_Alert := FALSE;
        END_IF;
END_CASE;

END_FUNCTION_BLOCK