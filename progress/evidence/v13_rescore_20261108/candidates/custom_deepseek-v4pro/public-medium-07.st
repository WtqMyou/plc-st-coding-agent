FUNCTION_BLOCK FB
VAR_INPUT
    OCCUPANCY_DETECTED: BOOL;
    ENERGY_SAVING_MODE: BOOL;
    HVAC_MODE_SELECTOR: INT;
END_VAR
VAR_OUTPUT
    SUPPLY_FAN_RUN: BOOL;
    TEMP_SETPOINT_ADJUST: INT;
END_VAR
VAR
    fan_delay_count: INT := 0;
END_VAR

(* Fan start delay logic - valid modes are 0(Auto),1(Comfort),2(Economy); Night(3) or invalid stop fan *)
IF OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR >= 0) AND (HVAC_MODE_SELECTOR <= 2) THEN
    IF fan_delay_count < 30 THEN
        fan_delay_count := fan_delay_count + 1;
    END_IF;
    IF fan_delay_count >= 30 THEN
        SUPPLY_FAN_RUN := TRUE;
    ELSE
        SUPPLY_FAN_RUN := FALSE;
    END_IF;
ELSE
    fan_delay_count := 0;
    SUPPLY_FAN_RUN := FALSE;
END_IF;

(* Temperature setpoint adjustment *)
CASE HVAC_MODE_SELECTOR OF
    0: (* Auto *)
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            IF ENERGY_SAVING_MODE THEN
                TEMP_SETPOINT_ADJUST := 3;
            ELSE
                TEMP_SETPOINT_ADJUST := 2;
            END_IF;
        END_IF;
    1: (* Comfort *)
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            TEMP_SETPOINT_ADJUST := 1;
        END_IF;
    2: (* Economy *)
        IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
        ELSE
            TEMP_SETPOINT_ADJUST := 4;
        END_IF;
    3: (* Night *)
        TEMP_SETPOINT_ADJUST := 4;
    ELSE
        TEMP_SETPOINT_ADJUST := 0; (* invalid mode safe side *)
END_CASE;

END_FUNCTION_BLOCK