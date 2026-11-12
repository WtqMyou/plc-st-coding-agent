FUNCTION_BLOCK FB_JamPumpControl
VAR_INPUT
    VISCOSITY_OK    : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime    : TIME;
    CycleTime       : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN          : BOOL;
    PUMP_MAINT_DUE   : BOOL;
    PUMP_RUNTIME_ACC : LTIME;
END_VAR
VAR
    ViscosityValid : BOOL := FALSE;
    DebounceTimer  : TON;
    tmp_MaintThreshold : LTIME := LTIME#500h;
END_VAR

(* CONTRACT_RULES [] *)

(* ENGINEERING_CONTRACT
+====================+================+==========+=========================+================+===============+
| Output/State       | Activation     | Retention| Reset/Deactivation      | Same-Scan Prio | Boundaries    |
+====================+================+==========+=========================+================+===============+
| VFD_RUN            | ESTOP=TRUE     | Hold     | Immediately on ESTOP=FALSE per PUB003 | Immediate disable | Boolean       |
|                    | AND            |          | No delay on ESTOP loss   |               |               |
|                    | ViscosityValid |          |                          |               |               |
+--------------------+----------------+----------+-------------------------+----------------+---------------+
| ViscosityValid     | TON.Q=TRUE     | Hold TRUE| Invalidate on           | Immediate      | Internal state|
| (internal)         | after          | while    | VISCOSITY_OK=FALSE      | invalidation   |               |
|                    | DebounceTime   | VISCOSITY_OK=TRUE        | per PUB002     |               |               |
+--------------------+----------------+----------+-------------------------+----------------+---------------+
| PUMP_RUNTIME_ACC   | +CycleTime     | Preserve | Only via power-up init  | Increment per  | LTIME, max    |
|                    | per scan while | when     | (PUB006). No auto-reset | scan when      | 500h threshold|
|                    | VFD_RUN=TRUE   | stopped  | specified.              | VFD_RUN=TRUE   | for PUMP_MAINT|
+--------------------+----------------+----------+-------------------------+----------------+---------------+
| PUMP_MAINT_DUE     | Set when       | Hold TRUE| Not specified (informational per PUB005) | At threshold | Boolean       |
|                    | ACC >= 500h    |          | No reset required       |               |               |
+--------------------+----------------+----------+-------------------------+----------------+---------------+
| DebounceTimer      | Start when     | Running  | Reset (ET=TRUE) on      | Clear on input | TON; PT=DebounceTime |
|                    | VISCOSITY_OK   | if input | VISCOSITY_OK=FALSE per  | drop (PUB002)  |               |
|                    | becomes TRUE   | stays TRUE| PUB002                 |               |               |
+--------------------+----------------+----------+-------------------------+----------------+---------------+
*)

CASE BOOL_TO_INT(PASTE_E_STOP_NC) OF
    0: // Emergency stop active
        VFD_RUN := FALSE;
        ViscosityValid := FALSE;
        DebounceTimer(IN := FALSE, PT := DebounceTime);
        
    1: // Emergency stop cleared - normal operation
        IF NOT VISCOSITY_OK THEN
            ViscosityValid := FALSE;
            DebounceTimer(IN := FALSE, PT := DebounceTime);
        ELSE
            DebounceTimer(IN := TRUE, PT := DebounceTime);
            ViscosityValid := DebounceTimer.Q;
        END_IF;
        
        VFD_RUN := ViscosityValid;
END_CASE;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + LTIME(CycleTime);
END_IF;

IF PUMP_RUNTIME_ACC >= tmp_MaintThreshold THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;

END_FUNCTION_BLOCK