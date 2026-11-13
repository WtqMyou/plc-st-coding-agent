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
    startupDelay : TON;
    gapDelay : TON;
END_VAR
startupDelay(IN := TRUE, PT := T#5s);
Weld_Soft_Start_Active := NOT startupDelay.Q;
gapDelay(IN := startupDelay.Q AND Weld_E_Stop_NC AND Gap_Exceeded, PT := DebounceTime);
Operator_Alert := gapDelay.Q;
END_FUNCTION_BLOCK
