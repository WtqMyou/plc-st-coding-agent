(* ENGINEERING_CONTRACT
 * | Output/State Group | Activation              | Retention         | Reset/Deactivation                  | Priority | Units/Bounds          |
 * |---------------------|-------------------------|-------------------|-------------------------------------|----------|-----------------------|
 * | SUPPLY_FAN_RUN      | 30s TON.Q after         | Hold TRUE while   | Deactivate and reset TON when:      | Same-scan| 30s PT, BOOLEAN       |
 * |   - Fan Start       |   Occupied=TRUE AND     |   conditions      |   Occupied=FALSE OR Mode=3 (Night)  |          |                       |
 * |                     |   Mode<>3, rising edge  |   maintained      |   Rising-edge reset on recovery     |          |                       |
 * |---------------------|-------------------------|-------------------|-------------------------------------|----------|-----------------------|
 * | TEMP_SETPOINT_ADJUST| Computed each scan from | Computed fresh    | Recalculated on any input change    | Same-scan| Auto: 0/+3/+2,        |
 * |   - Auto (Mode=0)   |   Mode × Occupancy ×    |   each scan       |   No explicit retention             |          |   Comfort: 0/+1,      |
 * |   - Comfort (Mode=1)|   EnergySaving combo    |                   |                                     |          |   Economy: 0/+4,      |
 * |   - Economy (Mode=2)|                         |                   |                                     |          |   Night: +4, ±4°C     |
 * |   - Night (Mode=3)  |                         |                   |                                     |          |                       |
 * PUB clause citations: PUB001, PUB002, PUB003, PUB004, PUB005, PUB006, PUB007, PUB008
 *)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB_HVAC_Control
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
    local_fan_start_cond : BOOL;
    local_prev_fan_start_cond : BOOL := FALSE;
    local_TON_30s : TON;
END_VAR
    // Determine fan start condition: occupied AND not Night mode
    local_fan_start_cond := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);

    // Rising-edge reset: if condition was false and now true, reset timer by toggling IN low
    IF local_fan_start_cond AND NOT local_prev_fan_start_cond THEN
        local_TON_30s(IN := FALSE, PT := T#30S);
    END_IF;

    // Run timer with current condition
    local_TON_30s(IN := local_fan_start_cond, PT := T#30S);

    // Update previous condition for next scan edge detection
    local_prev_fan_start_cond := local_fan_start_cond;

    // --- SUPPLY_FAN_RUN: 30-second delay from occupancy + non-Night start ---
    SUPPLY_FAN_RUN := local_TON_30s.Q;

    // --- TEMP_SETPOINT_ADJUST: Mode-based calculation, clamped to ±4°C ---
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

        3: // Night mode: always +4°C regardless of occupancy
            TEMP_SETPOINT_ADJUST := 4;

        ELSE
            ;
    END_CASE;

    // Clamp to ±4°C boundary
    IF TEMP_SETPOINT_ADJUST > 4 THEN
        TEMP_SETPOINT_ADJUST := 4;
    ELSIF TEMP_SETPOINT_ADJUST < -4 THEN
        TEMP_SETPOINT_ADJUST := -4;
    END_IF;
END_FUNCTION_BLOCK