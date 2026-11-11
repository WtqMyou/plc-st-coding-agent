(* -------------------------------------------------------------
   Office HVAC Multi‑mode Energy‑Saving Control
   -------------------------------------------------------------
   Inputs
     OCCUPANCY_DETECTED   – TRUE when occupancy is detected
     ENERGY_SAVING_MODE   – TRUE → energy‑saving, FALSE → standard
     HVAC_MODE_SELECTOR   – 0 = Auto, 1 = Comfort, 2 = Economy, 3 = Night
   Outputs
     SUPPLY_FAN_RUN       – Supply‑fan run enable (BOOL)
     TEMP_SETPOINT_ADJUST – Temperature‑setpoint adjustment in °C (INT)
   -------------------------------------------------------------
   Behaviour
     • 30 s on‑delay for the fan when occupied and NOT in Night mode.
       The fan is stopped immediately and the timer is reset when
       occupancy is lost or Night mode is entered.
     • Temperature‑setpoint adjustment follows the table:
       Mode   | Occupied | Unoccupied (standard) | Unoccupied (energy‑saving)
       -------|----------|-----------------------|----------------------------
       Auto   |   0 °C   |        +2 °C          |            +3 °C
       Comfort|   0 °C   |        +1 °C          |            +1 °C
       Economy|   0 °C   |        +4 °C          |            +4 °C
       Night  |   +4 °C  |        +4 °C          |            +4 °C
       (Energy‑saving flag influences only Auto mode.)
     • Outputs are initialised to OFF / 0 at power‑up and are updated
       every scan from the current inputs.
   ------------------------------------------------------------- *)

FUNCTION_BLOCK HVAC_Control
   VAR_INPUT
      OCCUPANCY_DETECTED   : BOOL;
      ENERGY_SAVING_MODE   : BOOL;
      HVAC_MODE_SELECTOR   : INT;
   END_VAR

   VAR_OUTPUT
      SUPPLY_FAN_RUN       : BOOL := FALSE;
      TEMP_SETPOINT_ADJUST : INT  := 0;
   END_VAR

   VAR
      FanTimer      : TON;
      FanStartCond  : BOOL;
   END_VAR

   (* ---------------------------------------------------------
      Fan start condition: occupied AND NOT Night mode
      --------------------------------------------------------- *)
   FanStartCond := OCCUPANCY_DETECTED AND (HVAC_MODE_SELECTOR <> 3);

   (* ---------------------------------------------------------
      30‑second ON‑delay timer
      The timer resets automatically when FanStartCond becomes FALSE,
      fulfilling the “reset timing if occupancy is lost or Night mode
      is selected” requirement.
      --------------------------------------------------------- *)
   FanTimer(IN := FanStartCond, PT := T#30s);
   SUPPLY_FAN_RUN := FanTimer.Q;

   (* ---------------------------------------------------------
      Temperature‑setpoint adjustment according to mode,
      occupancy and energy‑saving selection.
      --------------------------------------------------------- *)
   CASE HVAC_MODE_SELECTOR OF
      0 : (* Auto *)
         IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
         ELSE
            IF ENERGY_SAVING_MODE THEN
               TEMP_SETPOINT_ADJUST := 3;
            ELSE
               TEMP_SETPOINT_ADJUST := 2;
            END_IF;
         END_IF;

      1 : (* Comfort *)
         IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
         ELSE
            TEMP_SETPOINT_ADJUST := 1;
         END_IF;

      2 : (* Economy *)
         IF OCCUPANCY_DETECTED THEN
            TEMP_SETPOINT_ADJUST := 0;
         ELSE
            TEMP_SETPOINT_ADJUST := 4;
         END_IF;

      3 : (* Night *)
         TEMP_SETPOINT_ADJUST := 4;

   END_CASE;

END_FUNCTION_BLOCK