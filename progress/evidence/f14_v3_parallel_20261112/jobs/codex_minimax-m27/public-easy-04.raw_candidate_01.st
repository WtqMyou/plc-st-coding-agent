FUNCTION_BLOCK JamPumpControl
VAR_INPUT
    VISCOSITY_OK     : BOOL;
    PASTE_E_STOP_NC  : BOOL;
    DebounceTime     : TIME;
    CycleTime        : TIME;
END_VAR

VAR_OUTPUT
    VFD_RUN          : BOOL := FALSE;
    PUMP_MAINT_DUE   : BOOL := FALSE;
    PUMP_RUNTIME_ACC : LTIME := LTIME#0s;
END_VAR

VAR
    ViscosityValid        : BOOL := FALSE;
    ViscosityDebounceTmr  : LTIME := LTIME#0s;
END_VAR

// Viscosity debouncing
IF VISCOSITY_OK THEN
    IF NOT ViscosityValid THEN
        ViscosityDebounceTmr := ViscosityDebounceTmr + LTIME(CycleTime);
        IF ViscosityDebounceTmr >= LTIME(DebounceTime) THEN
            ViscosityValid := TRUE;
            ViscosityDebounceTmr := LTIME#0s;
        END_IF;
    END_IF;
ELSE
    ViscosityValid := FALSE;
    ViscosityDebounceTmr := LTIME#0s;
END_IF;

// Safety permissive: E-stop AND valid viscosity
IF PASTE_E_STOP_NC AND ViscosityValid THEN
    VFD_RUN := TRUE;
ELSE
    VFD_RUN := FALSE;
END_IF;

// Runtime accumulation while running
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + LTIME(CycleTime);
END_IF;

// Maintenance due at 500 hours
PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= LTIME#500h);

END_FUNCTION_BLOCK