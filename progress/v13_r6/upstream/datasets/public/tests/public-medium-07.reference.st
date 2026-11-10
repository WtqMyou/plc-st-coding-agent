(* =====================================================================
   public-medium-07  Office HVAC Multi-mode Energy-Saving Control
   ---------------------------------------------------------------------
   平台边界（《公共题制作约定》§7）：TIME 字面量解析为 0、TIME 加减恒为 0，
   因此需求 2 的"30 秒起动延时"用**扫描周期计数**实现：30 拍 = 30 s
   （1 拍 = 1 s）。用例按拍数断言，note 里注明"以周期数代替 30 s"。
   温度设定值修正是纯 INT 组合逻辑，不受平台边界影响。
   ===================================================================== *)
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
  delayCycles : INT;           (* R2: 30 s 延时 = 30 个扫描周期 *)
  fanPermit : BOOL;
END_VAR

(* R1: 合法型号只有 0/1/2/3；调用方应给合法值，非法值按安全侧处理 *)
modeValid := (HVAC_MODE_SELECTOR >= 0) AND (HVAC_MODE_SELECTOR <= 3);
nightMode := HVAC_MODE_SELECTOR = 3;

(* R2 / R7: 只有"占用 且 未选 Night 且 型号合法"才计时；
   延时只决定 BOOL 风扇许可，不涉及任何转速斜坡。
   失去占用或选中 Night（或型号非法）时立即停风扇并把计时清零，
   条件恢复后必须重新等满 30 拍。 *)
fanPermit := modeValid AND OCCUPANCY_DETECTED AND NOT nightMode;
IF fanPermit THEN
  IF delayCycles < 30 THEN
    delayCycles := delayCycles + 1;
  END_IF;
ELSE
  delayCycles := 0;
END_IF;
SUPPLY_FAN_RUN := delayCycles >= 30;

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
