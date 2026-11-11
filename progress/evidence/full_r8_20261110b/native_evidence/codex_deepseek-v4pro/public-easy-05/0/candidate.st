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
    PowerUpScans : INT := 0;
    GapTrueScans : INT := 0;
END_VAR

Weld_Soft_Start_Active := PowerUpScans < 5;

IF Weld_E_Stop_NC = FALSE THEN
    Operator_Alert := FALSE;
    GapTrueScans := 0;
ELSIF PowerUpScans < 5 THEN
    Operator_Alert := FALSE;
    GapTrueScans := 0;
ELSIF Gap_Exceeded THEN
    GapTrueScans := GapTrueScans + 1;
    IF GapTrueScans >= 3 THEN
        Operator_Alert := TRUE;
    ELSE
        Operator_Alert := FALSE;
    END_IF;
ELSE
    Operator_Alert := FALSE;
    GapTrueScans := 0;
END_IF;

IF PowerUpScans < 5 THEN
    PowerUpScans := PowerUpScans + 1;
END_IF;

END_FUNCTION_BLOCK