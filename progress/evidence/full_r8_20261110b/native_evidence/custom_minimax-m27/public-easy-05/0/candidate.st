FUNCTION_BLOCK FB
VAR_INPUT
    Gap_Exceeded    : BOOL;
    Weld_E_Stop_NC  : BOOL;
    DebounceTime    : TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert       : BOOL := FALSE;
    Weld_Soft_Start_Active : BOOL := TRUE;
END_VAR
VAR
    Scan_Count          : INT := 0;
    Consecutive_Count   : INT := 0;
    prev_Gap            : BOOL := FALSE;
    prev_prev_Gap       : BOOL := FALSE;
END_VAR

    Scan_Count := Scan_Count + 1;

    IF Scan_Count <= 5 THEN
        Weld_Soft_Start_Active := TRUE;
        Consecutive_Count := 0;
        Operator_Alert := FALSE;
    ELSE
        Weld_Soft_Start_Active := FALSE;

        IF NOT Weld_E_Stop_NC THEN
            Operator_Alert := FALSE;
            Consecutive_Count := 0;
        ELSIF Gap_Exceeded THEN
            Consecutive_Count := Consecutive_Count + 1;
            IF Consecutive_Count >= 3 THEN
                Operator_Alert := TRUE;
            END_IF;
        ELSE
            Operator_Alert := FALSE;
            Consecutive_Count := 0;
        END_IF;
    END_IF;

    prev_prev_Gap := prev_Gap;
    prev_Gap := Gap_Exceeded;
END_FUNCTION_BLOCK