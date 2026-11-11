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
    TON_30S        : TON;
    initDone       : BOOL := FALSE;
    fanCondition   : BOOL;
    adj            : INT;
END_VAR

IF NOT initDone THEN
    // Power-up initialization: outputs OFF and zero, reset timer
    SUPPLY_FAN_RUN      := FALSE;
    TEMP_SETPOINT_ADJUST := 0;
    TON_30S(IN := FALSE, PT := T#30s);
    initDone            := TRUE;
ELSE
    // Normal calculation
    // --- Supply fan start delay ---
    // Fan allowed only when occupied and not in Night mode (mode <> 3)
    fanCondition := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);
    TON_30S(IN := fanCondition, PT := T#30s);
    SUPPLY_FAN_RUN := TON_30S.Q;

    // --- Temperature setpoint adjustment ---
    adj := 0;
    CASE HVAC_MODE_SELECTOR OF
        0:  // Auto
            IF OCCUPANCY_DETECTED THEN
                adj := 0;
            ELSIF ENERGY_SAVING_MODE THEN
                adj := 3;
            ELSE
                adj := 2;
            END_IF;

        1:  // Comfort
            IF OCCUPANCY_DETECTED THEN
                adj := 0;
            ELSE
                adj := 1;
            END_IF;

        2:  // Economy
            IF OCCUPANCY_DETECTED THEN
                adj := 0;
            ELSE
                adj := 4;
            END_IF;

        3:  // Night
            adj := 4;
    END_CASE;

    // Clamp to ±4 °C
    IF adj < -4 THEN
        adj := -4;
    ELSIF adj > 4 THEN
        adj := 4;
    END_IF;
    TEMP_SETPOINT_ADJUST := adj;
END_IF;

END_FUNCTION_BLOCK