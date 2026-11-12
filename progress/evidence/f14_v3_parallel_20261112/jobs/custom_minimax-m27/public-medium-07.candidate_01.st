FUNCTION_BLOCK HVAC_Control
VAR_INPUT
    OCCUPANCY_DETECTED    : BOOL;
    ENERGY_SAVING_MODE    : BOOL;
    HVAC_MODE_SELECTOR    : INT;
END_VAR

VAR_OUTPUT
    SUPPLY_FAN_RUN        : BOOL := FALSE;
    TEMP_SETPOINT_ADJUST  : INT := 0;
END_VAR

VAR
    fanDelayTimer : TON;
    fanConditionsMet : BOOL;
    rawAdjustment : INT;
END_VAR

(* Fan delay logic: 30s on, instant off *)
fanConditionsMet := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);

fanDelayTimer(
    IN  := fanConditionsMet,
    PT  := T#30S
);

IF fanDelayTimer.Q THEN
    SUPPLY_FAN_RUN := TRUE;
ELSE
    SUPPLY_FAN_RUN := FALSE;
END_IF;

(* Temperature setpoint calculation *)
rawAdjustment := 0;

CASE HVAC_MODE_SELECTOR OF
    0: (* Auto mode *)
        IF OCCUPANCY_DETECTED THEN
            rawAdjustment := 0;
        ELSE
            IF ENERGY_SAVING_MODE THEN
                rawAdjustment := 3;
            ELSE
                rawAdjustment := 2;
            END_IF;
        END_IF;

    1: (* Comfort mode *)
        IF OCCUPANCY_DETECTED THEN
            rawAdjustment := 0;
        ELSE
            rawAdjustment := 1;
        END_IF;

    2: (* Economy mode *)
        IF OCCUPANCY_DETECTED THEN
            rawAdjustment := 0;
        ELSE
            rawAdjustment := 4;
        END_IF;

    3: (* Night mode *)
        rawAdjustment := 4;

ELSE
    rawAdjustment := 0;
END_CASE;

(* Clamp to ±4°C *)
IF rawAdjustment > 4 THEN
    TEMP_SETPOINT_ADJUST := 4;
ELSIF rawAdjustment < -4 THEN
    TEMP_SETPOINT_ADJUST := -4;
ELSE
    TEMP_SETPOINT_ADJUST := rawAdjustment;
END_IF;

END_FUNCTION_BLOCK