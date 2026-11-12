FUNCTION_BLOCK FB_WeldGapAlarm
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
    PowerUpTimer : TON;
    GapDebounceTimer : TON;
    InitializationDone : BOOL;
END_VAR

PowerUpTimer(IN := TRUE, PT := T#5S);
InitializationDone := PowerUpTimer.Q;

GapDebounceTimer(IN := Gap_Exceeded
                      AND Weld_E_Stop_NC
                      AND InitializationDone,
                 PT := DebounceTime);

Operator_Alert := GapDebounceTimer.Q;
Weld_Soft_Start_Active := NOT InitializationDone;

END_FUNCTION_BLOCK