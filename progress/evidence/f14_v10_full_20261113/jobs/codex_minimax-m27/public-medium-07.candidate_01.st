(* ENGINEERING_CONTRACT
 * HVAC Multi-mode Energy-Saving Control - Design Table
 * 
 * Output: SUPPLY_FAN_RUN (BOOL)
 *   - Activation:    30s TON delay when OCCUPANCY_DETECTED=TRUE AND HVAC_MODE_SELECTOR<>3
 *   - Retention:     Holds TRUE once elapsed >= 30s until deactivated
 *   - Reset:         Immediate deactivation when OCCUPANCY_DETECTED=FALSE OR HVAC_MODE_SELECTOR=3
 *   - Same-scan:     Evaluate conditions before TON, update outputs after TON
 *   - Units:         30 seconds, TON.ET saturates at PT
 *
 * Output: TEMP_SETPOINT_ADJUST (INT, clamped ±4°C)
 *   - PUB001 §3: Auto mode - occupied: 0°C; unoccupied + energy_saving: +3°C; unoccupied + standard: +2°C
 *   - PUB002 §4: Comfort mode - occupied: 0°C; unoccupied: +1°C
 *   - PUB003 §5: Economy mode - occupied: 0°C; unoccupied: +4°C
 *   - PUB004 §6: Night mode (3) - +4°C regardless of occupancy
 *   - Retention:   Updated every scan from current inputs; no state retention between scans
 *   - Boundaries:  Clamped to [-4, +4] inclusive
 *
 * Initialization:
 *   - SUPPLY_FAN_RUN := FALSE on power-up (PUB006)
 *   - TEMP_SETPOINT_ADJUST := 0 on power-up (PUB006)
 *   - Timer state initialized by TON at first call (implicit)
 *
 * Edge Cases:
 *   - Night mode selected: fan disabled immediately, no delay (PUB001)
 *   - Occupancy lost: fan disabled immediately, timer reset (PUB001)
 *   - Recovery: full 30s delay required again (PUB001)
 *   - HVAC_MODE_SELECTOR values 0-3 only; caller supplies valid value
 *)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK HVAC_MultiMode_Control
VAR_INPUT
    OCCUPANCY_DETECTED  : BOOL;
    ENERGY_SAVING_MODE  : BOOL;
    HVAC_MODE_SELECTOR  : INT;
END_VAR

VAR_OUTPUT
    SUPPLY_FAN_RUN      : BOOL := FALSE;
    TEMP_SETPOINT_ADJUST : INT := 0;
END_VAR

VAR
    FanDelayTimer : TON;
    prevOccupancy : BOOL := FALSE;
    tmpOccupied   : BOOL;
    tmpFanEnable  : BOOL;
    tmpAdjust     : INT;
END_VAR

(* Same-scan logic: determine conditions before timer, then act *)
tmpOccupied := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);

(* Fan enable request: occupied AND not night mode *)
tmpFanEnable := tmpOccupied;

(* Manage fan delay timer *)
IF tmpFanEnable THEN
    FanDelayTimer(IN := TRUE, PT := T#30S);
    (* TON.Q is TRUE when elapsed >= PT; TON.ET saturates at PT *)
    SUPPLY_FAN_RUN := FanDelayTimer.Q;
ELSE
    FanDelayTimer(IN := FALSE, PT := T#30S);
    SUPPLY_FAN_RUN := FALSE;
END_IF;

(* Temperature setpoint adjustment per mode *)
CASE HVAC_MODE_SELECTOR OF
    0: (* Auto mode *)
        IF OCCUPANCY_DETECTED THEN
            tmpAdjust := 0;
        ELSE
            IF ENERGY_SAVING_MODE THEN
                tmpAdjust := 3;
            ELSE
                tmpAdjust := 2;
            END_IF;
        END_IF;
        
    1: (* Comfort mode *)
        IF OCCUPANCY_DETECTED THEN
            tmpAdjust := 0;
        ELSE
            tmpAdjust := 1;
        END_IF;
        
    2: (* Economy mode *)
        IF OCCUPANCY_DETECTED THEN
            tmpAdjust := 0;
        ELSE
            tmpAdjust := 4;
        END_IF;
        
    3: (* Night mode *)
        tmpAdjust := 4;
        
    ELSE
        (* Fallback for invalid values; maintain last safe state *)
        tmpAdjust := 0;
END_CASE;

(* Clamp to ±4°C per PUB007 *)
IF tmpAdjust > 4 THEN
    tmpAdjust := 4;
ELSIF tmpAdjust < -4 THEN
    tmpAdjust := -4;
END_IF;

TEMP_SETPOINT_ADJUST := tmpAdjust;

(* Track occupancy for next scan *)
prevOccupancy := OCCUPANCY_DETECTED;

END_FUNCTION_BLOCK