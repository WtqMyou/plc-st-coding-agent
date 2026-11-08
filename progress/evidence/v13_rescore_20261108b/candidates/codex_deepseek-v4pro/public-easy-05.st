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
    InitCounter : INT := 5;
    DebounceCounter : INT := 0;
END_VAR

IF InitCounter > 0 THEN
    InitCounter := InitCounter - 1;
    Weld_Soft_Start_Active := TRUE;
    Operator_Alert := FALSE;
    DebounceCounter := 0;
ELSE
    Weld_Soft_Start_Active := FALSE;

    IF NOT Weld_E_Stop_NC THEN
        Operator_Alert := FALSE;
        DebounceCounter := 0;
    ELSIF Gap_Exceeded THEN
        IF DebounceCounter < 3 THEN
            DebounceCounter := DebounceCounter + 1;
        END_IF;
        Operator_Alert := (DebounceCounter >= 3);
    ELSE
        DebounceCounter := 0;
        Operator_Alert := FALSE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK