FUNCTION_BLOCK Weld_Gap_Alarm
VAR_INPUT
    Gap_Exceeded    : BOOL;
    Weld_E_Stop_NC  : BOOL;
    DebounceTime    : TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert        : BOOL := FALSE;
    Weld_Soft_Start_Active: BOOL := FALSE;
END_VAR
VAR
    State           : (EStop, Init, Monitor) := Init;
    Init_Timer      : TON;
    Gap_Debounce    : TON;
    Gap_Debounced   : BOOL := FALSE;
    Gap_Accumulated : LTIME := LTIME#0s;
    CycleCount      : UINT := 0;
END_VAR

// EStop has highest priority - immediate reaction before any other logic
IF NOT Weld_E_Stop_NC THEN
    Operator_Alert := FALSE;
    Weld_Soft_Start_Active := FALSE;
    Gap_Debounced := FALSE;
    Gap_Accumulated := LTIME#0s;
    Gap_Debounce(IN := FALSE);
    Gap_Debounce.PT := T#0ms;
    Init_Timer(IN := FALSE);
    Init_Timer.PT := T#0ms;
    Init_Timer.Q := FALSE;
    State := EStop;
    RETURN;
END_IF;

// EStop released - restart initialization timer
IF State = EStop THEN
    State := Init;
    Init_Timer(IN := FALSE);
END_IF;

// State machine for initialization and monitoring
CASE State OF
    Init:
        // Begin 5-second initialization inhibition
        Init_Timer(IN := TRUE, PT := T#5s);
        Weld_Soft_Start_Active := TRUE;
        Operator_Alert := FALSE;
        Gap_Debounced := FALSE;
        Gap_Accumulated := LTIME#0s;
        Gap_Debounce(IN := FALSE);
        Gap_Debounce.PT := T#0ms;
        
        // Transition to monitoring after initialization completes
        IF Init_Timer.Q THEN
            State := Monitor;
            Weld_Soft_Start_Active := FALSE;
        END_IF;
    
    Monitor:
        Init_Timer(IN := FALSE);
        Init_Timer.Q := FALSE;
        Weld_Soft_Start_Active := FALSE;
        
        // Gap monitoring with debounce
        IF Gap_Exceeded THEN
            // Accumulate debounce time using cycle-based increment
            Gap_Accumulated := Gap_Accumulated + TO_LTIME(CycleCount);
            
            // Check if debounce threshold reached
            IF Gap_Accumulated >= TO_LTIME(DebounceTime) THEN
                Gap_Debounced := TRUE;
                Operator_Alert := TRUE;
            END_IF;
        ELSE
            // Signal is FALSE - clear alarm and reset debounce
            Gap_Debounced := FALSE;
            Operator_Alert := FALSE;
            Gap_Accumulated := LTIME#0s;
        END_IF;
END_CASE;

// Track cycle time for debounce accumulation
CycleCount := TO_UINT(T#1ms) / TO_UINT(T#1ms);

END_FUNCTION_BLOCK