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
    fan_delay : TON;                 // On‑delay timer for 30 s start delay
END_VAR

// Initialise outputs to safe state
SUPPLY_FAN_RUN       := FALSE;
TEMP_SETPOINT_ADJUST := 0;

// ----- Temperature setpoint adjustment -----
IF HVAC_MODE_SELECTOR = 3 THEN
    // Night mode: +4 °C regardless of occupancy
    TEMP_SETPOINT_ADJUST := 4;
ELSE
    // Non‑night modes (Auto, Comfort, Economy)
    IF OCCUPANCY_DETECTED THEN
        TEMP_SETPOINT_ADJUST := 0;
    ELSE
        // Unoccupied – adjustment depends on mode and energy‑saving selection
        CASE HVAC_MODE_SELECTOR OF
            0: // Auto
                IF ENERGY_SAVING_MODE THEN
                    TEMP_SETPOINT_ADJUST := 3;   // +3 °C in energy‑saving
                ELSE
                    TEMP_SETPOINT_ADJUST := 2;   // +2 °C in standard
                END_IF
            1: // Comfort
                TEMP_SETPOINT_ADJUST := 1;       // +1 °C
            2: // Economy
                TEMP_SETPOINT_ADJUST := 4;       // +4 °C
            ELSE
                // Invalid mode – safe side 0 °C
                TEMP_SETPOINT_ADJUST := 0;
        END_CASE
    END_IF
END_IF

// ----- Supply fan on‑delay (30 s) -----
// Timer runs only while occupied AND not in Night mode
fan_delay(IN := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3), PT := T#30s);
SUPPLY_FAN_RUN := fan_delay.Q;
END_FUNCTION_BLOCK