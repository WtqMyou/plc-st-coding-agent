FUNCTION_BLOCK FB
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
    start_delay_timer : TON;
    delay_condition : BOOL;
    calculated_adjustment : INT;
END_VAR

SUPPLY_FAN_RUN := FALSE;
TEMP_SETPOINT_ADJUST := 0;

delay_condition := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);

start_delay_timer(
    IN := delay_condition,
    PT := T#30s
);

IF delay_condition THEN
    SUPPLY_FAN_RUN := start_delay_timer.Q;
ELSE
    SUPPLY_FAN_RUN := FALSE;
END_IF;

CASE HVAC_MODE_SELECTOR OF
    0:
        IF OCCUPANCY_DETECTED THEN
            calculated_adjustment := 0;
        ELSE
            IF ENERGY_SAVING_MODE THEN
                calculated_adjustment := 3;
            ELSE
                calculated_adjustment := 2;
            END_IF;
        END_IF;

    1:
        IF OCCUPANCY_DETECTED THEN
            calculated_adjustment := 0;
        ELSE
            calculated_adjustment := 1;
        END_IF;

    2:
        IF OCCUPANCY_DETECTED THEN
            calculated_adjustment := 0;
        ELSE
            calculated_adjustment := 4;
        END_IF;

    3:
        calculated_adjustment := 4;

ELSE
    calculated_adjustment := 0;
END_CASE;

IF calculated_adjustment < -4 THEN
    TEMP_SETPOINT_ADJUST := -4;
ELSIF calculated_adjustment > 4 THEN
    TEMP_SETPOINT_ADJUST := 4;
ELSE
    TEMP_SETPOINT_ADJUST := calculated_adjustment;
END_IF;

END_FUNCTION_BLOCK