FUNCTION_BLOCK FB
VAR_INPUT
    OCCUPANCY_DETECTED   : BOOL;
    ENERGY_SAVING_MODE   : BOOL;
    HVAC_MODE_SELECTOR   : INT;
END_VAR
VAR_OUTPUT
    SUPPLY_FAN_RUN       : BOOL;
    TEMP_SETPOINT_ADJUST : INT;
END_VAR
VAR
    DelayTimer : TON;
END_VAR

// ----- Initialize outputs at power-up -----
SUPPLY_FAN_RUN       := FALSE;
TEMP_SETPOINT_ADJUST := 0;

// ----- Temperature setpoint adjustment -----
IF HVAC_MODE_SELECTOR = 3 THEN
    TEMP_SETPOINT_ADJUST := 4;
ELSE
    IF OCCUPANCY_DETECTED THEN
        TEMP_SETPOINT_ADJUST := 0;
    ELSE
        CASE HVAC_MODE_SELECTOR OF
            0:
                IF ENERGY_SAVING_MODE THEN
                    TEMP_SETPOINT_ADJUST := 3;
                ELSE
                    TEMP_SETPOINT_ADJUST := 2;
                END_IF
            1:
                TEMP_SETPOINT_ADJUST := 1;
            2:
                TEMP_SETPOINT_ADJUST := 4;
            ELSE
                TEMP_SETPOINT_ADJUST := 0;
        END_CASE
    END_IF
END_IF;

// Clamp to ±4°C
IF TEMP_SETPOINT_ADJUST > 4 THEN
    TEMP_SETPOINT_ADJUST := 4;
ELSIF TEMP_SETPOINT_ADJUST < -4 THEN
    TEMP_SETPOINT_ADJUST := -4;
END_IF;

// ----- Supply fan 30-second on-delay -----
DelayTimer(IN := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3), PT := T#30S);
SUPPLY_FAN_RUN := DelayTimer.Q;
END_FUNCTION_BLOCK