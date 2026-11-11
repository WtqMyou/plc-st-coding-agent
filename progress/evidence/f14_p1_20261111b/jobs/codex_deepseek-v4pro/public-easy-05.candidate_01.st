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

// 5-second power-up initialization inhibition
PowerUpTimer(IN := TRUE, PT := T#5S);
Weld_Soft_Start_Active := NOT PowerUpTimer.Q;

// Gap debounce only after initialization and while emergency stop is inactive
GapTimer(
    IN := Gap_Exceeded
          AND PowerUpTimer.Q
          AND Weld_E_Stop_NC,
    PT := DebounceTime
);

// Alarm only after full debounce, and emergency stop overrides immediately
Operator_Alert := GapTimer.Q AND Weld_E_Stop_NC;