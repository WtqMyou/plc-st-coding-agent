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
    occupancy_delay_timer : TON;
END_VAR

// Fan control with 30-second delay
IF OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3) THEN
    occupancy_delay_timer(IN := TRUE, PT := T#30S);
    IF occupancy_delay_timer.Q THEN
        SUPPLY_FAN_RUN := TRUE;
    ELSE
        SUPPLY_FAN_RUN := FALSE;
    END_IF;
ELSE
    occupancy_delay_timer(IN := FALSE);
    SUPPLY_FAN_RUN := FALSE;
END_IF;

// Temperature setpoint adjustment per mode
CASE HVAC_MODE_SELECTOR OF
    0: // Auto
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            TEMP_SETPOINT_ADJUST := BOOL_TO_INT(ENERGY_SAVING_MODE) + 2;
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
    ELSE
        TEMP_SETPOINT_ADJUST := 0;
END_CASE;

// Clamp to ±4°C
IF TEMP_SETPOINT_ADJUST > 4 THEN
    TEMP_SETPOINT_ADJUST := 4;
ELSIF TEMP_SETPOINT_ADJUST < -4 THEN
    TEMP_SETPOINT_ADJUST := -4;
END_IF;

END_FUNCTION_BLOCK