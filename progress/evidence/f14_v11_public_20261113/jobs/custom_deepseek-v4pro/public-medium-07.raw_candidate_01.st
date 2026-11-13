FUNCTION_BLOCK OfficeHVACMultiModeControl

(* ENGINEERING_CONTRACT
PUB001: HVAC_MODE_SELECTOR valid 0..3; assumption: input is valid.
PUB002: SUPPLY_FAN_RUN active when OCCUPANCY_DETECTED AND mode<>3 remain true for 30s via TON.
  Activation: TON.Q after 30s; Hold: conditions remain true; Reset: occupancy lost or mode=3,
  timer IN false => immediate Q false and ET reset; same-scan final value from current inputs.
PUB003-PUB005: TEMP_SETPOINT_ADJUST combinational from current mode, occupancy, energy-saving.
  Auto: occ 0, unocc ES +3, unocc std +2. Comfort: occ 0, unocc +1.
  Economy: occ 0, unocc +4. Night: +4 regardless of occupancy. Units degrees C.
  Clamp -4..+4. Energy-saving affects Auto mode only.
PUB006: outputs initialized FALSE/0 by declaration/start scan; no independent retained output outside timer.
PUB007: 30s delay controls only BOOL fan enable.
*)

(* CONTRACT_RULES
[]
*)

VAR
    tmp_delayActive : BOOL;
    tmp_fanTimer    : TON;
    tmp_adjust      : INT;
    tmp_mode        : INT;
    tmp_occ         : BOOL;
    tmp_es          : BOOL;
END_VAR

SUPPLY_FAN_RUN := FALSE;
TEMP_SETPOINT_ADJUST := 0;

tmp_mode := HVAC_MODE_SELECTOR;
tmp_occ  := OCCUPANCY_DETECTED;
tmp_es   := ENERGY_SAVING_MODE;

tmp_delayActive := tmp_occ AND (tmp_mode <> 3);
tmp_fanTimer(IN := tmp_delayActive, PT := T#30S);
SUPPLY_FAN_RUN := tmp_fanTimer.Q;

CASE tmp_mode OF
  0:
    IF tmp_occ THEN
      tmp_adjust := 0;
    ELSE
      IF tmp_es THEN
        tmp_adjust := 3;
      ELSE
        tmp_adjust := 2;
      END_IF;
    END_IF;

  1:
    IF tmp_occ THEN
      tmp_adjust := 0;
    ELSE
      tmp_adjust := 1;
    END_IF;

  2:
    IF tmp_occ THEN
      tmp_adjust := 0;
    ELSE
      tmp_adjust := 4;
    END_IF;

  3:
    tmp_adjust := 4;

  ELSE
    tmp_adjust := 0;
END_CASE;

IF tmp_adjust > 4 THEN
  tmp_adjust := 4;
ELSIF tmp_adjust < -4 THEN
  tmp_adjust := -4;
END_IF;

TEMP_SETPOINT_ADJUST := tmp_adjust;

END_FUNCTION_BLOCK