FUNCTION_BLOCK JamPumpDebounce
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime : TIME;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL := FALSE;
    PUMP_MAINT_DUE : BOOL := FALSE;
    PUMP_RUNTIME_ACC : LTIME := LTIME#0s;
END_VAR
VAR
    ViscosityValid : BOOL := FALSE;
    DebounceElapsed : LTIME := LTIME#0s;
END_VAR

IF NOT VISCOSITY_OK THEN
    ViscosityValid := FALSE;
    DebounceElapsed := LTIME#0s;
ELSIF NOT PASTE_E_STOP_NC THEN
    DebounceElapsed := LTIME#0s;
ELSIF NOT ViscosityValid THEN
    DebounceElapsed := DebounceElapsed + TO_LTIME(CycleTime);
    IF DebounceElapsed >= TO_LTIME(DebounceTime) THEN
        ViscosityValid := TRUE;
        DebounceElapsed := TO_LTIME(DebounceTime);
    END_IF;
END_IF;

VFD_RUN := PASTE_E_STOP_NC AND ViscosityValid;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(CycleTime);
END_IF;

IF PUMP_RUNTIME_ACC >= TO_LTIME(T#500H) THEN
    PUMP_MAINT_DUE := TRUE;
ELSE
    PUMP_MAINT_DUE := FALSE;
END_IF;

END_FUNCTION_BLOCK