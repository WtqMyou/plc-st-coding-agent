(*
ENGINEERING_CONTRACT
1. DebounceValid state: set only while VISCOSITY_OK=TRUE and PASTE_E_STOP_NC=TRUE after accumulated CycleTime >= DebounceTime; immediate invalidation when VISCOSITY_OK=FALSE; incomplete timing is cleared when E-stop is FALSE (PUB001, PUB002).
2. VFD_RUN: active = PASTE_E_STOP_NC AND DebounceValid; E-stop has immediate priority and disables output in the same scan; no output latching (PUB002).
3. PUMP_RUNTIME_ACC: accumulates TO_LTIME(CycleTime) only when same-scan VFD_RUN=TRUE; preserves accumulated time while stopped; initial value 0 (PUB003, PUB005).
4. PUMP_MAINT_DUE: set when PUMP_RUNTIME_ACC >= LTIME#500H; because runtime is monotonic, it remains set; informational only with no effect on run/permissive logic (PUB004).
5. Initialization: VFD_RUN=FALSE, PUMP_RUNTIME_ACC=LTIME#0S, PUMP_MAINT_DUE=FALSE via declared initial values (PUB005).
Boundary: threshold comparisons use >= and TIME values are converted to LTIME; first satisfying debounce tick occurs when accumulated CycleTime reaches DebounceTime.
Unspecified: non-positive DebounceTime or CycleTime are assumed to be supplied positive (PUB006).
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK JamPump
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime : TIME;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL := FALSE;
    PUMP_MAINT_DUE : BOOL := FALSE;
    PUMP_RUNTIME_ACC : LTIME := LTIME#0S;
END_VAR
VAR
    local_DebounceElapsed : LTIME := LTIME#0S;
    local_ViscCondValid : BOOL := FALSE;
    local_MaintenanceLimit : LTIME := LTIME#500H;
END_VAR

IF NOT VISCOSITY_OK THEN
    local_ViscCondValid := FALSE;
    local_DebounceElapsed := LTIME#0S;
ELSE
    IF NOT PASTE_E_STOP_NC THEN
        IF NOT local_ViscCondValid THEN
            local_DebounceElapsed := LTIME#0S;
        END_IF;
    ELSE
        IF NOT local_ViscCondValid THEN
            local_DebounceElapsed := local_DebounceElapsed + TO_LTIME(CycleTime);
            IF local_DebounceElapsed >= TO_LTIME(DebounceTime) THEN
                local_ViscCondValid := TRUE;
            END_IF;
        END_IF;
    END_IF;
END_IF;

VFD_RUN := PASTE_E_STOP_NC AND local_ViscCondValid;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(CycleTime);
END_IF;

PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= local_MaintenanceLimit);

END_FUNCTION_BLOCK