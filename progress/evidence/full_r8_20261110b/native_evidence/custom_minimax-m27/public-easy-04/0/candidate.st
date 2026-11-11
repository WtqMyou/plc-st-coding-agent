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
    debounceAccum : DINT := 0;
    prevValid : BOOL := FALSE;
END_VAR

IF (PASTE_E_STOP_NC AND VISCOSITY_OK) THEN
    IF NOT prevValid THEN
        debounceAccum := CycleMs;
    ELSE
        debounceAccum := debounceAccum + CycleMs;
    END_IF;
ELSE
    debounceAccum := 0;
END_IF;

VFD_RUN := (PASTE_E_STOP_NC AND VISCOSITY_OK) AND (debounceAccum >= DebounceMs);

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LINT(CycleMs);
END_IF;

PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= 1800000000);

prevValid := (PASTE_E_STOP_NC AND VISCOSITY_OK);

END_FUNCTION_BLOCK