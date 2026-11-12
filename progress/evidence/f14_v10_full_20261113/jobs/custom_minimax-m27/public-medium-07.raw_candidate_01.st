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
VAR
    local_TON_Start : TON;
    local_prev_occupied_and_not_night : BOOL := FALSE;
END_VAR
VAR_OUTPUT
    SUPPLY_FAN_RUN : BOOL := FALSE;
    TEMP_SETPOINT_ADJUST : INT := 0;
END_VAR

    // --- Rising-edge detection for timer reset ---
    // Timer resets to zero on first scan when conditions become satisfied
    IF OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3) THEN
        IF NOT local_prev_occupied_and_not_night THEN
            local_TON_Start(EN := FALSE, PT := T#30S);
            local_TON_Start.ET := T#0S;
        END_IF
        local_TON_Start(EN := TRUE, PT := T#30S);
        local_prev_occupied_and_not_night := TRUE;
    ELSE
        // Conditions not satisfied: stop timer, reset accumulated time
        local_TON_Start(EN := FALSE, PT := T#30S);
        local_TON_Start.ET := T#0S;
        local_prev_occupied_and_not_night := FALSE;
    END_IF;

    // --- SUPPLY_FAN_RUN: 30-second delay from occupancy + non-Night start ---
    SUPPLY_FAN_RUN := local_TON_Start.Q;

    // --- TEMP_SETPOINT_ADJUST: Mode-based calculation, clamped to ±4°C ---
    // PUB001: Mode 0 (Auto), PUB003: Mode 1 (Comfort), PUB004: Mode 2 (Economy), PUB005: Mode 3 (Night)
    CASE HVAC_MODE_SELECTOR OF
        0: // Auto mode
            IF OCCUPANCY_DETECTED THEN
                TEMP_SETPOINT_ADJUST := 0;
            ELSE
                IF ENERGY_SAVING_MODE THEN
                    TEMP_SETPOINT_ADJUST := 3; // PUB006: +3°C unoccupied in energy-saving
                ELSE
                    TEMP_SETPOINT_ADJUST := 2; // PUB006: +2°C unoccupied in standard
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
            // Invalid mode: retain previous value (caller guarantees valid input)
            ;
    END_CASE;

    // Clamp to ±4°C boundary (PUB007)
    IF TEMP_SETPOINT_ADJUST > 4 THEN
        TEMP_SETPOINT_ADJUST := 4;
    ELSIF TEMP_SETPOINT_ADJUST < -4 THEN
        TEMP_SETPOINT_ADJUST := -4;
    END_IF;

END_FUNCTION_BLOCK