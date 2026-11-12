FUNCTION_BLOCK OfficeHVACMultiModeControl
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
    fan_timer : TON;
    setpoint_calc : INT;
END_VAR

fan_timer(IN := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3), PT := T#30S);
SUPPLY_FAN_RUN := fan_timer.Q;

CASE HVAC_MODE_SELECTOR OF
    0:
        IF OCCUPANCY_DETECTED THEN
            setpoint_calc := 0;
        ELSIF ENERGY_SAVING_MODE THEN
            setpoint_calc := 3;
        ELSE
            setpoint_calc := 2;
        END_IF;
    1:
        IF OCCUPANCY_DETECTED THEN
            setpoint_calc := 0;
        ELSE
            setpoint_calc := 1;
        END_IF;
    2:
        IF OCCUPANCY_DETECTED THEN
            setpoint_calc := 0;
        ELSE
            setpoint_calc := 4;
        END_IF;
    3:
        setpoint_calc := 4;
    ELSE
        setpoint_calc := 0;
END_CASE;

IF setpoint_calc > 4 THEN
    TEMP_SETPOINT_ADJUST := 4;
ELSIF setpoint_calc < -4 THEN
    TEMP_SETPOINT_ADJUST := -4;
ELSE
    TEMP_SETPOINT_ADJUST := setpoint_calc;
END_IF;
END_FUNCTION_BLOCK