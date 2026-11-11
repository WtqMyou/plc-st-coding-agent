FUNCTION_BLOCK FB
VAR_INPUT
    OCCUPANCY_DETECTED : BOOL;
    ENERGY_SAVING_MODE : BOOL;
    HVAC_MODE_SELECTOR : INT;
END_VAR
VAR_OUTPUT
    SUPPLY_FAN_RUN : BOOL := FALSE;
    TEMP_SETPOINT_ADJUST : INT := 0;
END_VAR
VAR
    delayCounter : INT := 0;
END_VAR

// Fan enable with 30-cycle (scan) delay
IF (OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3)) THEN
    IF delayCounter < 30 THEN
        delayCounter := delayCounter + 1;
    END_IF;
    IF delayCounter >= 30 THEN
        SUPPLY_FAN_RUN := TRUE;
    ELSE
        SUPPLY_FAN_RUN := FALSE;
    END_IF;
ELSE
    delayCounter := 0;
    SUPPLY_FAN_RUN := FALSE;
END_IF;

// Temperature setpoint adjustment calculation
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
    ELSE
        // Invalid mode -> safe default 0
        TEMP_SETPOINT_ADJUST := 0;
END_CASE;

END_FUNCTION_BLOCK