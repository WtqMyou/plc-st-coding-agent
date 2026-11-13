(* CONTRACT_RULES [] *)
(* ENGINEERING_CONTRACT
Group | Activation | Retention | Reset | Same-scan priority | Units/boundaries
SUPPLY_FAN_RUN | enable=OCCUPANCY_DETECTED AND HVAC_MODE_SELECTOR<>3 for T#30S continuously | TON holds Q true while enable true and elapsed>=PT | IN false clears ET and Q on same call | timer called before Q copied | BOOL, seconds (PUB002,PUB007)
TEMP_SETPOINT_ADJUST | valid mode combinational from current inputs | none; recomputed each scan | next input scan overwrites | clamp after raw calculation | INT degC, [-4,4] (PUB003-PUB006)
*)
FUNCTION_BLOCK OfficeHVACControl
VAR_INPUT
    OCCUPANCY_DETECTED : BOOL;
    ENERGY_SAVING_MODE : BOOL;
    HVAC_MODE_SELECTOR : INT;
END_VAR
VAR_OUTPUT
    SUPPLY_FAN_RUN : BOOL;
    TEMP_SETPOINT_ADJUST : INT;
END_VAR
VAR
    local_fan_timer : TON;
    local_fan_enable : BOOL;
    local_raw_adjust : INT;
END_VAR

local_fan_enable := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);
local_fan_timer(IN := local_fan_enable, PT := T#30S);
SUPPLY_FAN_RUN := local_fan_timer.Q;

CASE HVAC_MODE_SELECTOR OF
    0:
        IF OCCUPANCY_DETECTED THEN
            local_raw_adjust := 0;
        ELSIF ENERGY_SAVING_MODE THEN
            local_raw_adjust := 3;
        ELSE
            local_raw_adjust := 2;
        END_IF;
    1:
        IF OCCUPANCY_DETECTED THEN
            local_raw_adjust := 0;
        ELSE
            local_raw_adjust := 1;
        END_IF;
    2:
        IF OCCUPANCY_DETECTED THEN
            local_raw_adjust := 0;
        ELSE
            local_raw_adjust := 4;
        END_IF;
    3:
        local_raw_adjust := 4;
    ELSE
        local_raw_adjust := 0;
END_CASE;

IF local_raw_adjust < -4 THEN
    TEMP_SETPOINT_ADJUST := -4;
ELSIF local_raw_adjust > 4 THEN
    TEMP_SETPOINT_ADJUST := 4;
ELSE
    TEMP_SETPOINT_ADJUST := local_raw_adjust;
END_IF;

END_FUNCTION_BLOCK