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
    fanDelay : TON;
    startFanCondition : BOOL;
    adjustment : INT;
END_VAR

    SUPPLY_FAN_RUN := FALSE;
    TEMP_SETPOINT_ADJUST := 0;

    startFanCondition := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);
    fanDelay(IN := startFanCondition, PT := T#30S);
    SUPPLY_FAN_RUN := fanDelay.Q;

    IF HVAC_MODE_SELECTOR = 0 THEN
        IF OCCUPANCY_DETECTED THEN
            adjustment := 0;
        ELSE
            IF ENERGY_SAVING_MODE THEN
                adjustment := 3;
            ELSE
                adjustment := 2;
            END_IF;
        END_IF;
    ELSIF HVAC_MODE_SELECTOR = 1 THEN
        IF OCCUPANCY_DETECTED THEN
            adjustment := 0;
        ELSE
            adjustment := 1;
        END_IF;
    ELSIF HVAC_MODE_SELECTOR = 2 THEN
        IF OCCUPANCY_DETECTED THEN
            adjustment := 0;
        ELSE
            adjustment := 4;
        END_IF;
    ELSIF HVAC_MODE_SELECTOR = 3 THEN
        adjustment := 4;
    ELSE
        adjustment := 0;
    END_IF;

    IF adjustment > 4 THEN
        adjustment := 4;
    ELSIF adjustment < -4 THEN
        adjustment := -4;
    END_IF;

    TEMP_SETPOINT_ADJUST := adjustment;

END_FUNCTION_BLOCK