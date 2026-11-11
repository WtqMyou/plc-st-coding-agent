FUNCTION_BLOCK WeldGapAlarm
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
    InitTimer : TON;
    DebounceTimer : TON;
    InitDone : BOOL;
    E_StopActive : BOOL;
END_VAR

// Emergency stop active when NC contact is open (FALSE)
E_StopActive := NOT Weld_E_Stop_NC;

// 5-second power-up initialization timer
InitTimer(IN := TRUE, PT := T#5s);
InitDone := InitTimer.Q;

// Soft-start active only during the initial inhibition period
Weld_Soft_Start_Active := NOT InitDone;

// Debounce timer runs only during normal monitoring, after initialization,
// and when the emergency stop is not active.
// If Gap_Exceeded drops or E-stop becomes active, the timer resets (clears).
DebounceTimer(IN := Gap_Exceeded AND InitDone AND NOT E_StopActive,
              PT := DebounceTime);

// Alarm output follows the debounced gap-exceeded condition
Operator_Alert := DebounceTimer.Q;

END_FUNCTION_BLOCK