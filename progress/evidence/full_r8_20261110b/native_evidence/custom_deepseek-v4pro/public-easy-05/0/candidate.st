FUNCTION_BLOCK FB
VAR_INPUT
    Gap_Exceeded: BOOL;
    Weld_E_Stop_NC: BOOL;
    DebounceTime: TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert: BOOL;
    Weld_Soft_Start_Active: BOOL;
END_VAR
VAR
    scan_count: INT := 0;
    debounce_count: INT := 0;
END_VAR

scan_count := scan_count + 1;

IF scan_count <= 5 THEN
    Weld_Soft_Start_Active := TRUE;
ELSE
    Weld_Soft_Start_Active := FALSE;
END_IF

IF NOT Weld_E_Stop_NC THEN
    Operator_Alert := FALSE;
    debounce_count := 0;
ELSIF Weld_Soft_Start_Active THEN
    Operator_Alert := FALSE;
    debounce_count := 0;
ELSE
    IF Gap_Exceeded THEN
        debounce_count := debounce_count + 1;
    ELSE
        debounce_count := 0;
    END_IF
    IF debounce_count >= 3 THEN
        Operator_Alert := TRUE;
    ELSE
        Operator_Alert := FALSE;
    END_IF
END_IF

END_FUNCTION_BLOCK