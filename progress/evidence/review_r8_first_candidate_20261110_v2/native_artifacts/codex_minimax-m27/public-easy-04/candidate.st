FUNCTION_BLOCK FB
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceMs : DINT;
    CycleMs : DINT;
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL;
    PUMP_MAINT_DUE : BOOL;
    PUMP_RUNTIME_ACC : LINT;
END_VAR
VAR
    PrevCycleMs : DINT := 0;
    PrevCondition : BOOL := FALSE;
    DebounceDuration : DINT := 0;
END_VAR

IF PASTE_E_STOP_NC AND VISCOSITY_OK THEN
    DebounceDuration := DebounceDuration + CycleMs;
    VFD_RUN := (DebounceDuration >= DebounceMs);
ELSE
    DebounceDuration := 0;
    VFD_RUN := FALSE;
END_IF;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleMs;
END_IF;

PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= 1800000000);

PrevCondition := (PASTE_E_STOP_NC AND VISCOSITY_OK);
PrevCycleMs := CycleMs;
END_FUNCTION_BLOCK