FUNCTION_BLOCK FB
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
    First_Scan : BOOL := TRUE;
    ConsecutiveCount : INT := 0;
    InitScanCounter : INT := 0;
END_VAR

    IF First_Scan THEN
        First_Scan := FALSE;
        Operator_Alert := FALSE;
        Weld_Soft_Start_Active := TRUE;
        ConsecutiveCount := 0;
        InitScanCounter := 0;
    ELSE
        InitScanCounter := InitScanCounter + 1;

        IF InitScanCounter <= 5 THEN
            Weld_Soft_Start_Active := TRUE;
            Operator_Alert := FALSE;
            ConsecutiveCount := 0;
        ELSE
            Weld_Soft_Start_Active := FALSE;

            IF NOT Weld_E_Stop_NC THEN
                Operator_Alert := FALSE;
                ConsecutiveCount := 0;
            ELSIF Gap_Exceeded THEN
                ConsecutiveCount := ConsecutiveCount + 1;
                IF ConsecutiveCount >= 3 THEN
                    Operator_Alert := TRUE;
                ELSE
                    Operator_Alert := FALSE;
                END_IF
            ELSE
                ConsecutiveCount := 0;
                Operator_Alert := FALSE;
            END_IF
        END_IF
    END_IF
END_FUNCTION_BLOCK