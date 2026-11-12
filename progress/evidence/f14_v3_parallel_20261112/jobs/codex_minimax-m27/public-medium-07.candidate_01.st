FUNCTION_BLOCK HVAC_Controller
VAR_INPUT
    OCCUPANCY_DETECTED      : BOOL;
    ENERGY_SAVING_MODE      : BOOL;
    HVAC_MODE_SELECTOR      : INT;
END_VAR

VAR_OUTPUT
    SUPPLY_FAN_RUN          : BOOL;
    TEMP_SETPOINT_ADJUST    : INT;
END_VAR

VAR
    OccupancyTimer          : TON;
    OccupancyStartTime      : LTIME;
    FanDelayActive          : BOOL := FALSE;
    FanDelayElapsed         : BOOL := FALSE;
    PreviousOccupancy       : BOOL := FALSE;
END_VAR

// Fan control logic
IF NOT OCCUPANCY_DETECTED OR (HVAC_MODE_SELECTOR = 3) THEN
    // Reset delay when occupancy lost or Night mode selected
    FanDelayActive := FALSE;
    FanDelayElapsed := FALSE;
    SUPPLY_FAN_RUN := FALSE;
    OccupancyTimer(IN := FALSE);
ELSIF OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3) THEN
    // Start delay when occupancy detected and not in Night mode
    IF NOT FanDelayActive THEN
        FanDelayActive := TRUE;
        OccupancyTimer(IN := FALSE);
    END_IF;
    OccupancyTimer(IN := TRUE, PT := T#30S);
    FanDelayElapsed := OccupancyTimer.Q;
    SUPPLY_FAN_RUN := FanDelayElapsed;
ELSE
    // Default to off
    SUPPLY_FAN_RUN := FALSE;
END_IF;

// Temperature setpoint calculation
CASE HVAC_MODE_SELECTOR OF
    0: // Auto mode
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            IF ENERGY_SAVING_MODE THEN
                TEMP_SETPOINT_ADJUST := 3;
            ELSE
                TEMP_SETPOINT_ADJUST := 2;
            END_IF;
        END_IF;

    1: // Comfort mode
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            TEMP_SETPOINT_ADJUST := 1;
        END_IF;

    2: // Economy mode
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            TEMP_SETPOINT_ADJUST := 4;
        END_IF;

    3: // Night mode
        TEMP_SETPOINT_ADJUST := 4;

ELSE
    TEMP_SETPOINT_ADJUST := 0;
END_CASE;

// Clamp to ±4°C
IF TEMP_SETPOINT_ADJUST > 4 THEN
    TEMP_SETPOINT_ADJUST := 4;
ELSIF TEMP_SETPOINT_ADJUST < -4 THEN
    TEMP_SETPOINT_ADJUST := -4;
END_IF;

PreviousOccupancy := OCCUPANCY_DETECTED;

END_FUNCTION_BLOCK