FUNCTION_BLOCK HVACMultiModeControl
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
    tmp_Delay : TON;
    tmp_Enable : BOOL;
    tmp_Adjust : INT;
END_VAR

(* ENGINEERING_CONTRACT
   SUPPLY_FAN_RUN [PUB002, PUB005]: enabled only while occupancy exists
   and HVAC_MODE_SELECTOR <> 3; TON 30 s drives the output. Losing the
   enable condition stops output and resets timing on the same scan;
   recovery requires a complete new 30 s interval.
   TEMP_SETPOINT_ADJUST [PUB003, PUB004]: recomputed each scan. Auto is
   0/3/2, Comfort 0/1, Economy 0/4, Night 4; energy saving affects Auto
   only. Result is clamped to [-4, +4] °C.
   Init state: outputs OFF and 0 at power-up; invalid selector uses 0 °C.
*)

(* CONTRACT_RULES [] *)

SUPPLY_FAN_RUN := FALSE;
TEMP_SETPOINT_ADJUST := 0;

tmp_Enable := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);
tmp_Delay(IN := tmp_Enable, PT := T#30S);
SUPPLY_FAN_RUN := tmp_Delay.Q;

CASE HVAC_MODE_SELECTOR OF
    0:
        IF OCCUPANCY_DETECTED THEN
            tmp_Adjust := 0;
        ELSIF ENERGY_SAVING_MODE THEN
            tmp_Adjust := 3;
        ELSE
            tmp_Adjust := 2;
        END_IF;
    1:
        IF OCCUPANCY_DETECTED THEN
            tmp_Adjust := 0;
        ELSE
            tmp_Adjust := 1;
        END_IF;
    2:
        IF OCCUPANCY_DETECTED THEN
            tmp_Adjust := 0;
        ELSE
            tmp_Adjust := 4;
        END_IF;
    3:
        tmp_Adjust := 4;
    ELSE
        tmp_Adjust := 0;
END_CASE;

IF tmp_Adjust < -4 THEN
    tmp_Adjust := -4;
ELSIF tmp_Adjust > 4 THEN
    tmp_Adjust := 4;
END_IF;

TEMP_SETPOINT_ADJUST := tmp_Adjust;
END_FUNCTION_BLOCK