(*
ENGINEERING_CONTRACT
VFD_RUN [PUB002,PUB003,PUB006]: TRUE only while PASTE_E_STOP_NC=TRUE and the viscosity debounce timer has elapsed; same-scan emergency stop drops the run command and clears incomplete debounce timing; power-up state is OFF.
Debounce [PUB002,PUB003]: timer IN uses VISCOSITY_OK AND PASTE_E_STOP_NC with PT=DebounceTime; a FALSE viscosity input invalidates immediately, and a FALSE emergency stop resets incomplete timing.
Runtime [PUB004,PUB006]: adds TIME_TO_LTIME(CycleTime) once per invocation only while VFD_RUN=TRUE; preserves the accumulated value while stopped; starts at 0 ns.
Maintenance [PUB005,PUB006]: PUMP_MAINT_DUE becomes TRUE when accumulated runtime reaches 500 h; it is informational only, remains TRUE because runtime is monotonic, and does not affect run or safety logic; starts FALSE.
Units/boundaries: maintenance threshold uses T#500h with >= comparison; CycleTime and DebounceTime are assumed positive.
Unspecified: no reset is defined for accumulated runtime or the maintenance indication; non-positive input times follow normal TON/add behavior without additional clamping.
*)
FUNCTION_BLOCK JamPumpControl
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime : TIME;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL;
    PUMP_MAINT_DUE : BOOL;
    PUMP_RUNTIME_ACC : LTIME;
END_VAR
VAR
    tonViscosity : TON;
    RuntimeAcc : LTIME := LTIME#0s;
    MAINT_THRESHOLD : TIME := T#500h;
END_VAR

tonViscosity(IN := (VISCOSITY_OK AND PASTE_E_STOP_NC), PT := DebounceTime);

VFD_RUN := PASTE_E_STOP_NC AND tonViscosity.Q;

IF VFD_RUN THEN
    RuntimeAcc := RuntimeAcc + TIME_TO_LTIME(CycleTime);
END_IF;

PUMP_RUNTIME_ACC := RuntimeAcc;
PUMP_MAINT_DUE := PUMP_RUNTIME_ACC >= TIME_TO_LTIME(MAINT_THRESHOLD);

END_FUNCTION_BLOCK