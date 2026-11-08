FUNCTION_BLOCK FB
VAR_INPUT
    VISCOSITY_OK     : BOOL;
    PASTE_E_STOP_NC  : BOOL;
    DebounceTime     : TIME;
    CycleTime        : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN          : BOOL;
    PUMP_MAINT_DUE   : BOOL;
    PUMP_RUNTIME_ACC : LINT;
END_VAR
VAR
    visc_debounce_acc : TIME := T#0s;
    visc_valid        : BOOL := FALSE;
END_VAR

// Debounce logic for viscosity condition
IF NOT VISCOSITY_OK THEN
    visc_debounce_acc := T#0s;
    visc_valid        := FALSE;
ELSIF visc_debounce_acc < DebounceTime THEN
    visc_debounce_acc := visc_debounce_acc + CycleTime;
    IF visc_debounce_acc >= DebounceTime THEN
        visc_debounce_acc := DebounceTime;
        visc_valid        := TRUE;
    END_IF
END_IF;

// VFD run permissive: E-STOP must be closed AND viscosity debounced valid
VFD_RUN := PASTE_E_STOP_NC AND visc_valid;

// Accumulate runtime (in hours) only while pump is running
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LINT(TIME_TO_INT(CycleTime) / 3600000);
END_IF;

// Maintenance due indication at 500 hours
PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= 500);
END_FUNCTION_BLOCK