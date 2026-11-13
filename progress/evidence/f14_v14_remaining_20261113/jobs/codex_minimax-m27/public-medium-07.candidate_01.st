FUNCTION_BLOCK HVAC_Control
(*
ENGINEERING_CONTRACT
| Output/State      | Activation              | Retention           | Reset/Deactivation        | Priority   | Units/Bounds       |
|-------------------|-------------------------|---------------------|---------------------------|------------|--------------------|
| SUPPLY_FAN_RUN    | Occupied + Non-Night,   | Hold while cond met | Unoccupied OR Night mode  | Same-scan  | 30s delay (LTIME)  |
|                   | after 30s TON.Q         |                     | resets TON, stops fan     |            |                    |
| TEMP_SETPOINT_    | Every scan from         | Hold last computed  | Re-evaluated each scan    | Same-scan  | INT ±4°C           |
| ADJUST            | HVAC_MODE_SELECTOR +    | value               | based on mode+occupancy   |            |                    |
|                   | OCCUPANCY_DETECTED +    |                     |                           |            |                    |
|                   | ENERGY_SAVING_MODE      |                     |                           |            |                    |
PUB001: Start 30s delay when OCCUPANCY_DETECTED AND HVAC_MODE_SELECTOR<>3
PUB002: Reset timer and stop fan if OCCUPANCY_DETECTED=FALSE OR HVAC_MODE_SELECTOR=3
PUB003: Temp adj: Auto(0°occ, +3°unocc_ES, +2°unocc_std), Comfort(0°occ, +1°unocc), Economy(0°occ, +4°unocc)
PUB004: Night: +4°C regardless of occupancy
PUB005: ENERGY_SAVING_MODE affects Auto mode only
PUB006: TEMP_SETPOINT_ADJUST within ±4°C
PUB007: Initialize outputs OFF/zero at power-up; update from current inputs
PUB008: Fan start delay controls only BOOL fan enable; no speed ramp
*)
VAR_INPUT
    OCCUPANCY_DETECTED  : BOOL;
    ENERGY_SAVING_MODE  : BOOL;
    HVAC_MODE_SELECTOR  : INT;
END_VAR

VAR_OUTPUT
    SUPPLY_FAN_RUN        : BOOL := FALSE;
    TEMP_SETPOINT_ADJUST  : INT := 0;
END_VAR

VAR
    fanTimer : TON;
END_VAR

// Fan control with 30-second start delay (PUB001, PUB002)
fanTimer(IN := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3), PT := T#30s);
IF fanTimer.Q THEN
    SUPPLY_FAN_RUN := TRUE;
ELSE
    SUPPLY_FAN_RUN := FALSE;
END_IF;

// Temperature setpoint adjustment (PUB003, PUB004, PUB005, PUB006)
CASE HVAC_MODE_SELECTOR OF
    0: // Auto
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            IF ENERGY_SAVING_MODE THEN
                TEMP_SETPOINT_ADJUST := 3;
            ELSE
                TEMP_SETPOINT_ADJUST := 2;
            END_IF;
        END_IF;
    1: // Comfort
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            TEMP_SETPOINT_ADJUST := 1;
        END_IF;
    2: // Economy
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            TEMP_SETPOINT_ADJUST := 4;
        END_IF;
    3: // Night
        TEMP_SETPOINT_ADJUST := 4;
END_CASE;

// Clamp to ±4°C boundary (PUB006)
IF TEMP_SETPOINT_ADJUST > 4 THEN TEMP_SETPOINT_ADJUST := 4; END_IF;
IF TEMP_SETPOINT_ADJUST < -4 THEN TEMP_SETPOINT_ADJUST := -4; END_IF;

END_FUNCTION_BLOCK