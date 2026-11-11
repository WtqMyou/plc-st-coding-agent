PROGRAM JamPumpControl
VAR
    ViscosityDebounceTimer : TON;
    ViscosityConditionValid : BOOL := FALSE;
    FirstScan : BOOL := TRUE;
END_VAR

// Power-up initialization
IF FirstScan THEN
    VFD_RUN := FALSE;
    PUMP_RUNTIME_ACC := LTIME#0s;
    PUMP_MAINT_DUE := FALSE;
    ViscosityConditionValid := FALSE;
    FirstScan := FALSE;
END_IF;

// Viscosity debouncing logic
IF NOT VISCOSITY_OK THEN
    ViscosityConditionValid := FALSE;
    ViscosityDebounceTimer(IN := FALSE);
ELSE
    ViscosityDebounceTimer(IN := TRUE, PT := DebounceTime);
    IF ViscosityDebounceTimer.Q THEN
        ViscosityConditionValid := TRUE;
    END_IF;
END_IF;

// VFD_RUN control with E-STOP and viscosity permission
IF PASTE_E_STOP_NC AND ViscosityConditionValid THEN
    VFD_RUN := TRUE;
ELSE
    VFD_RUN := FALSE;
END_IF;

// Runtime accumulation while pump is running
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleTime;
END_IF;

// Maintenance due indication at 500 hours
PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= LTIME#500h);

END_PROGRAM