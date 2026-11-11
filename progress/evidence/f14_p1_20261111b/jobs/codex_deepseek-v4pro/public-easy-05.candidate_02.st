FUNCTION_BLOCK WeldGapAlarm
VAR_INPUT
    Gap_Exceeded       : BOOL;
    Weld_E_Stop_NC     : BOOL;
    DebounceTime       : TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert         : BOOL;
    Weld_Soft_Start_Active : BOOL;
END_VAR
VAR
    PowerUpTimer  : TON;
    GapTimer      : TON;
END_VAR

PowerUpTimer(IN := TRUE, PT := T#5S);
Weld_Soft_Start_Active := NOT PowerUpTimer.Q;

GapTimer(
    IN := Gap_Exceeded
          AND PowerUpTimer.Q
          AND Weld_E_Stop_NC,
    PT := DebounceTime
);

Operator_Alert := GapTimer.Q AND Weld_E_Stop_NC;

END_FUNCTION_BLOCK