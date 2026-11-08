FUNCTION_BLOCK FB
VAR_INPUT
    Gap_Exceeded : BOOL;
    Weld_E_Stop_NC : BOOL;
    DebounceTime : TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert : BOOL;
    Weld_Soft_Start_Active : BOOL;
END_VAR
VAR
    init_cycle_count : INT := 5;
    gap_exceeded_prev : BOOL := FALSE;
    debounce_counter : INT := 0;
    debounce_required : INT := 50;
END_VAR

// Emergency stop priority - immediate reset regardless of state
IF NOT Weld_E_Stop_NC THEN
    Operator_Alert := FALSE;
    debounce_counter := 0;
    Weld_Soft_Start_Active := FALSE;
    gap_exceeded_prev := Gap_Exceeded;
    RETURN;
END_IF;

// Power-up initialization inhibition (5 scan cycles)
IF init_cycle_count > 0 THEN
    init_cycle_count := init_cycle_count - 1;
    Weld_Soft_Start_Active := TRUE;
    Operator_Alert := FALSE;
    debounce_counter := 0;
    gap_exceeded_prev := Gap_Exceeded;
    RETURN;
END_IF;

Weld_Soft_Start_Active := FALSE;
gap_exceeded_prev := Gap_Exceeded;

// Gap monitoring with debounce
IF Gap_Exceeded THEN
    debounce_counter := debounce_counter + 1;
    IF debounce_counter >= debounce_required THEN
        Operator_Alert := TRUE;
    ELSE
        Operator_Alert := FALSE;
    END_IF;
ELSE
    debounce_counter := 0;
    Operator_Alert := FALSE;
END_IF;
END_FUNCTION_BLOCK