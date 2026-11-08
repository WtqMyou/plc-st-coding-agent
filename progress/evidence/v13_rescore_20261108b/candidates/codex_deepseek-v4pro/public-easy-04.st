FUNCTION_BLOCK FB
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime : TIME;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL;
    PUMP_MAINT_DUE : BOOL;
    PUMP_RUNTIME_ACC : LINT;
END_VAR
VAR
    ViscosityValid : BOOL := FALSE;
    DebounceElapsed : TIME := T#0ms;
    RuntimeTicks : LINT := 0;
END_VAR

VFD_RUN := FALSE;

IF NOT VISCOSITY_OK THEN
    ViscosityValid := FALSE;
    DebounceElapsed := T#0ms;
ELSIF NOT PASTE_E_STOP_NC THEN
    DebounceElapsed := T#0ms;
ELSIF NOT ViscosityValid THEN
    DebounceElapsed := DebounceElapsed + CycleTime;
    IF DebounceElapsed >= DebounceTime THEN
        ViscosityValid := TRUE;
        DebounceElapsed := DebounceTime;
    END_IF
END_IF

IF PASTE_E_STOP_NC AND ViscosityValid THEN
    VFD_RUN := TRUE;
END_IF

IF VFD_RUN THEN
    RuntimeTicks := RuntimeTicks + TIME_TO_LINT(CycleTime);
END_IF

PUMP_RUNTIME_ACC := RuntimeTicks / TIME_TO_LINT(T#1h);

IF RuntimeTicks >= TIME_TO_LINT(T#500h) THEN
    PUMP_MAINT_DUE := TRUE;
ELSE
    PUMP_MAINT_DUE := FALSE;
END_IF

END_FUNCTION_BLOCK