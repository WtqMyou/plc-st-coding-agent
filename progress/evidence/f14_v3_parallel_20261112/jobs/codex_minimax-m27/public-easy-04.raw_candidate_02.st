FUNCTION_BLOCK JamPumpControl
VAR_INPUT
    VISCOSITY_OK    : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime    : TIME;
    CycleTime       : TIME;
END_VAR

VAR_OUTPUT
    VFD_RUN          : BOOL := FALSE;
    PUMP_MAINT_DUE   : BOOL := FALSE;
    PUMP_RUNTIME_ACC : LTIME := LTIME#0s;
END_VAR

VAR
    ViscosityValid       : BOOL := FALSE;
    ViscosityDebounceTmr : LTIME := LTIME#0s;
END_VAR

IF VISCOSITY_OK THEN
    IF NOT ViscosityValid THEN
        ViscosityDebounceTmr := ViscosityDebounceTmr + CycleTime;
        IF ViscosityDebounceTmr >= DebounceTime THEN
            ViscosityValid := TRUE;
            ViscosityDebounceTmr := LTIME#0s;
        END_IF;
    END_IF;
ELSE
    ViscosityValid := FALSE;
    ViscosityDebounceTmr := LTIME#0s;
END_IF;

IF PASTE_E_STOP_NC AND ViscosityValid THEN
    VFD_RUN := TRUE;
ELSE
    VFD_RUN := FALSE;
END_IF;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleTime;
END_IF;

PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= LTIME#500h);

END_FUNCTION_BLOCK