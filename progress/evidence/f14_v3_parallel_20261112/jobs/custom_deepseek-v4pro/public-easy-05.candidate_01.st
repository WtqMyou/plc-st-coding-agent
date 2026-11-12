FUNCTION_BLOCK WeldGapAlarm
VAR
    TON_Init     : TON;
    TON_Debounce : TON;
    InitActive   : BOOL;
    DebounceInput: BOOL;
END_VAR

TON_Init(IN := TRUE, PT := T#5S);
InitActive := NOT TON_Init.Q;

DebounceInput := Gap_Exceeded AND NOT InitActive AND Weld_E_Stop_NC;
TON_Debounce(IN := DebounceInput, PT := DebounceTime);

Operator_Alert := TON_Debounce.Q AND Weld_E_Stop_NC AND NOT InitActive;
Weld_Soft_Start_Active := InitActive AND Weld_E_Stop_NC;

END_FUNCTION_BLOCK