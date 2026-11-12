(*
ENGINEERING_CONTRACT
- VFD_RUN: active iff PASTE_E_STOP_NC AND viscosity_condition; no retention; immediate off on raw FALSE or E_STOP FALSE; PUB003.
- viscosity_condition: becomes TRUE when VISCOSITY_OK TRUE for >= DebounceTime; raw FALSE invalidates immediately; E_STOP clears only incomplete debounce; PUB002/PUB003.
- PUMP_RUNTIME_ACC: adds TIME_TO_LTIME(CycleTime) only when final VFD_RUN TRUE; preserved while stopped; starts at zero; PUB004/PUB006.
- PUMP_MAINT_DUE: TRUE when PUMP_RUNTIME_ACC >= TIME_TO_LTIME(T#500H); informational, no run/permissive effect; PUB005.
- units: DebounceTime/CycleTime TIME ms; accumulated value LTIME ns.
- priority: raw viscosity FALSE and E_STOP FALSE are resolved before same-scan runtime accumulation.
*)
(* CONTRACT_RULES [] *)

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
    local_debounce_elapsed : LTIME := LTIME#0S;
    local_viscosity_condition : BOOL := FALSE;
    local_runtime_accumulator : LTIME := LTIME#0S;
END_VAR

IF VISCOSITY_OK THEN
    IF PASTE_E_STOP_NC THEN
        IF CycleTime > T#0MS THEN
            IF local_debounce_elapsed < TIME_TO_LTIME(DebounceTime) THEN
                local_debounce_elapsed := local_debounce_elapsed + TIME_TO_LTIME(CycleTime);
                IF local_debounce_elapsed > TIME_TO_LTIME(DebounceTime) THEN
                    local_debounce_elapsed := TIME_TO_LTIME(DebounceTime);
                END_IF;
            END_IF;
        END_IF;
    ELSE
        IF local_debounce_elapsed < TIME_TO_LTIME(DebounceTime) THEN
            local_debounce_elapsed := LTIME#0S;
            local_viscosity_condition := FALSE;
        END_IF;
    END_IF;
    local_viscosity_condition := local_debounce_elapsed >= TIME_TO_LTIME(DebounceTime);
ELSE
    local_debounce_elapsed := LTIME#0S;
    local_viscosity_condition := FALSE;
END_IF;

VFD_RUN := PASTE_E_STOP_NC AND local_viscosity_condition;

IF VFD_RUN THEN
    IF CycleTime > T#0MS THEN
        local_runtime_accumulator := local_runtime_accumulator + TIME_TO_LTIME(CycleTime);
    END_IF;
END_IF;

PUMP_RUNTIME_ACC := local_runtime_accumulator;
PUMP_MAINT_DUE := local_runtime_accumulator >= TIME_TO_LTIME(T#500H);

END_FUNCTION_BLOCK