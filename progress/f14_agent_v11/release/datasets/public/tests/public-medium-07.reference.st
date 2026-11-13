FUNCTION_BLOCK FB_HVAC_ModeControl
VAR_INPUT
  OCCUPANCY_DETECTED : BOOL;   (* 占用检测结果（由 CO2 传感器导出） *)
  ENERGY_SAVING_MODE : BOOL;   (* TRUE=节能，FALSE=标准；只影响 Auto 模式 *)
  HVAC_MODE_SELECTOR : INT;    (* 0 Auto / 1 Comfort / 2 Economy / 3 Night *)
END_VAR
VAR_OUTPUT
  SUPPLY_FAN_RUN : BOOL;       (* 送风机运行许可 *)
  TEMP_SETPOINT_ADJUST : INT;  (* 温度设定值修正（摄氏度） *)
END_VAR
VAR
  modeValid : BOOL;            (* R1: 型号是否在合法集合 {0,1,2,3} 内 *)
  nightMode : BOOL;
  startDelay : TON;
  fanPermit : BOOL;
END_VAR

(* R1: 合法型号只有 0/1/2/3；调用方应给合法值，非法值按安全侧处理 *)
modeValid := (HVAC_MODE_SELECTOR >= 0) AND (HVAC_MODE_SELECTOR <= 3);
nightMode := HVAC_MODE_SELECTOR = 3;

fanPermit := modeValid AND OCCUPANCY_DETECTED AND NOT nightMode;
startDelay(IN := fanPermit, PT := T#30s);
SUPPLY_FAN_RUN := startDelay.Q;

(* R3 / R4 / R5 / R6: 温度设定值修正表
   - Night(3) 恒 +4，与占用无关；
   - 占用时一律 0（Night 已在上一支处理）；
   - Auto(0) 未占用：节能 +3 / 标准 +2（ENERGY_SAVING_MODE 只在这里生效）；
   - Comfort(1) 未占用 +1；Economy(2) 未占用 +4；
   - 非法型号（R1 之外）：需求未定义，按安全侧给 0。 *)
IF NOT modeValid THEN
  TEMP_SETPOINT_ADJUST := 0;
ELSIF nightMode THEN
  TEMP_SETPOINT_ADJUST := 4;
ELSIF OCCUPANCY_DETECTED THEN
  TEMP_SETPOINT_ADJUST := 0;
ELSIF HVAC_MODE_SELECTOR = 0 THEN
  IF ENERGY_SAVING_MODE THEN
    TEMP_SETPOINT_ADJUST := 3;
  ELSE
    TEMP_SETPOINT_ADJUST := 2;
  END_IF;
ELSIF HVAC_MODE_SELECTOR = 1 THEN
  TEMP_SETPOINT_ADJUST := 1;
ELSE
  TEMP_SETPOINT_ADJUST := 4;   (* Economy 未占用 *)
END_IF;

(* R6: ±4 °C 限幅；上电初值 FALSE/0 由平台默认初值保证 *)
TEMP_SETPOINT_ADJUST := LIMIT(-4, TEMP_SETPOINT_ADJUST, 4);

END_FUNCTION_BLOCK
