PROGRAM HVAC_Control
VAR
    // Inputs
    OCCUPANCY_DETECTED    : BOOL;
    ENERGY_SAVING_MODE    : BOOL;
    HVAC_MODE_SELECTOR    : INT;
    
    // Outputs
    SUPPLY_FAN_RUN        : BOOL := FALSE;
    TEMP_SETPOINT_ADJUST  : INT := 0;
    
    // Internal variables
    occupancy_delay_timer : TON;
END_VAR

//====================================================================
// SUPPLY FAN CONTROL - 30 second delay logic
//====================================================================
// Start 30-second delay when:
//   - Occupancy is detected
//   - Night mode (3) is NOT selected
// Stop immediately and reset timing if:
//   - Occupancy is lost
//   - Night mode is selected
//====================================================================
IF OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3) THEN
    // Start timing with 30-second preset
    occupancy_delay_timer(IN := TRUE, PT := T#30S);
    
    // Enable fan only after delay completes
    IF occupancy_delay_timer.Q THEN
        SUPPLY_FAN_RUN := TRUE;
    ELSE
        SUPPLY_FAN_RUN := FALSE;
    END_IF;
ELSE
    // Conditions lost - stop fan and reset timer
    occupancy_delay_timer(IN := FALSE);
    SUPPLY_FAN_RUN := FALSE;
END_IF;

//====================================================================
// TEMPERATURE SETPOINT ADJUSTMENT
//====================================================================
// Auto mode (0): 0°C when occupied; +3°C (energy saving) or +2°C (standard) when unoccupied
// Comfort mode (1): 0°C when occupied; +1°C when unoccupied
// Economy mode (2): 0°C when occupied; +4°C when unoccupied
// Night mode (3): +4°C regardless of occupancy
//====================================================================
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

//====================================================================
// CLAMP TO VALID RANGE ±4°C
//====================================================================
IF TEMP_SETPOINT_ADJUST > 4 THEN
    TEMP_SETPOINT_ADJUST := 4;
ELSIF TEMP_SETPOINT_ADJUST < -4 THEN
    TEMP_SETPOINT_ADJUST := -4;
END_IF;

END_PROGRAM