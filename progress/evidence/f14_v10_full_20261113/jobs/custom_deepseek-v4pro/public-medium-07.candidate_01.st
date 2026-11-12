FUNCTION_BLOCK Office_HVAC_MultiMode_EnergySaving
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
    local_FanStart : BOOL;
    local_FanTimer : TON;
    local_TempAdjust : INT;
END_VAR

(* ENGINEERING_CONTRACT
   SUPPLY_FAN_RUN: active only after 30 s continuous OCCUPANCY_DETECTED=TRUE and Night not selected (PUB002).
   SUPPLY_FAN_RUN: reset immediately if occupancy lost or Night selected; TON resets and full 30 s required again (PUB002).
   SUPPLY_FAN_RUN: BOOL enable only; no continuous speed ramp (PUB007).
   TEMP_SETPOINT_ADJUST: combinational from current mode, occupancy and Auto-only energy-saving flag (PUB003/PUB004/PUB005).
   TEMP_SETPOINT_ADJUST: INT degrees C, clamped to [-4,4]; no retention or explicit reset (PUB006).
   Initialization: variables start FALSE/0; normal calculation then updates outputs from current inputs (PUB006).
   Valid selector values are 0..3; callers guarantee this (PUB001). Invalid selector handling is unspecified and maps to 0 C adjustment.
*)

(* CONTRACT_RULES [] *)

local_FanStart := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);

local_FanTimer(IN := local_FanStart, PT := T#30S);
SUPPLY_FAN_RUN := local_FanTimer.Q;

CASE HVAC_MODE_SELECTOR OF
    0: (* Auto *)
        IF OCCUPANCY_DETECTED THEN
            local_TempAdjust := 0;
        ELSIF ENERGY_SAVING_MODE THEN
            local_TempAdjust := 3;
        ELSE
            local_TempAdjust := 2;
        END_IF;

    1: (* Comfort *)
        IF OCCUPANCY_DETECTED THEN
            local_TempAdjust := 0;
        ELSE
            local_TempAdjust := 1;
        END_IF;

    2: (* Economy *)
        IF OCCUPANCY_DETECTED THEN
            local_TempAdjust := 0;
        ELSE
            local_TempAdjust := 4;
        END_IF;

    3: (* Night *)
        local_TempAdjust := 4;

ELSE
    local_TempAdjust := 0; (* unspecified invalid input handling *)
END_CASE;

IF local_TempAdjust > 4 THEN
    local_TempAdjust := 4;
ELSIF local_TempAdjust < -4 THEN
    local_TempAdjust := -4;
END_IF;

TEMP_SETPOINT_ADJUST := local_TempAdjust;

END_FUNCTION_BLOCK