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
    ValidAccum : LINT;
    DebounceLimit : LINT;
    CycleDuration : LINT;
END_VAR

CycleDuration := CycleMs;
DebounceLimit := DebounceMs;

IF VISCOSITY_OK AND PASTE_E_STOP_NC THEN
    ValidAccum := ValidAccum + CycleDuration;
    VFD_RUN := ValidAccum >= DebounceLimit;
ELSE
    ValidAccum := 0;
    VFD_RUN := FALSE;
END_IF

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleDuration;
END_IF

IF PUMP_RUNTIME_ACC >= 1800000000 THEN
    PUMP_MAINT_DUE := TRUE;
ELSE
    PUMP_MAINT_DUE := FALSE;
END_IF

END_FUNCTION_BLOCK