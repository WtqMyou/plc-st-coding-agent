PROGRAM JamPumpControl
VAR
    ViscosityDebounceTimer : TON;
    ViscosityConditionValid : BOOL := FALSE;
END_VAR

// Power-up initialization
IF __SYSTEM__:*FIRSTSCAN THEN
    VFD_RUN := FALSE;
    PUMP_RUNTIME_ACC := LTIME#0s;
    PUMP_MAINT_DUE := FALSE;
    ViscosityConditionValid := FALSE;
END_IF;

// Viscosity debouncing logic
// Invalidate immediately when input becomes FALSE
IF NOT VISCOSITY_OK THEN
    ViscosityConditionValid := FALSE;
    ViscosityDebounceTimer(IN := FALSE);
ELSE
    // Start or continue timing when viscosity is good
    ViscosityDebounceTimer(IN := TRUE, PT := DebounceTime);
    
    // Condition is valid only after timer completes
    IF ViscosityDebounceTimer.Q THEN
        ViscosityConditionValid := TRUE;
    END_IF;
END_IF;

// Emergency stop and run permission logic
// VFD_RUN allowed only when E-STOP is OK AND viscosity is valid
IF PASTE_E_STOP_NC AND ViscosityConditionValid THEN
    VFD_RUN := TRUE;
ELSE
    VFD_RUN := FALSE;
END_IF;

// Runtime accumulation (accumulates only while VFD_RUN is TRUE)
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleTime;
END_IF;

// Maintenance due indication (500 hours)
PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= LTIME#500h);

END_PROGRAM