(* 公开题 public-easy-04：Jam Pump Debouncing and Runtime Maintenance
   平台偏差（契约 §7，2026-10-24 实测）：TIME 字面量恒为 0、TIME 加减恒为 0，
   所以 DebounceTime / CycleTime 在数值上没有信息量。本题改用**扫描周期计数**：
     * 去抖：连续 3 个扫描周期 VISCOSITY_OK=TRUE 视为"持续了 DebounceTime"；
     * 累计：VFD_RUN=TRUE 的每个扫描周期记为 1 小时（1 拍 = 1 h），
       于是"500 小时"= 500 个运行拍，维护阈值仍是需求里的 500。
   用例按周期数断言，偏差在每条用例的 note 与回报里写明。 *)
FUNCTION_BLOCK FB_JamPump
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime : TIME;   (* 平台恒为 0，见文件头偏差说明 *)
    CycleTime : TIME;      (* 平台恒为 0，见文件头偏差说明 *)
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL;
    PUMP_MAINT_DUE : BOOL;
    PUMP_RUNTIME_ACC : LINT;
END_VAR
VAR
    debounceCount : INT;     (* 连续有效拍数（代替 DebounceTime） *)
    viscosityValid : BOOL;   (* 去抖后的粘度条件 *)
    runHours : INT;          (* 已累计的运行拍数（= 小时数），用于阈值比较 *)
    initialized : BOOL;      (* 上电首拍标志 *)
END_VAR

(* R5: 上电初始化——首拍把三个输出显式清零，避免实例带保留存储时
   残留上一台泵的运行累计值。 *)
IF NOT initialized THEN
    initialized := TRUE;
    VFD_RUN := FALSE;
    PUMP_MAINT_DUE := FALSE;
    (* LINT 不能直接吃整数常量 0（类型检查会报 INT → LINT 不匹配），
       用"自己减自己"清零，语义等价且类型一致 *)
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC - PUMP_RUNTIME_ACC;
    debounceCount := 0;
    viscosityValid := FALSE;
    runHours := 0;
END_IF

(* R2: 急停优先于一切——先清去抖计数与粘度有效位，再判启动。
   顺序不能反：任何"先判粘度"的写法都会让急停那一拍还带着上一拍的
   粘度有效位，VFD_RUN 会晚一拍断开。 *)
IF NOT PASTE_E_STOP_NC THEN
    debounceCount := 0;          (* R2: 清掉不完整的去抖计时 *)
    viscosityValid := FALSE;
ELSIF VISCOSITY_OK THEN
    IF debounceCount < 3 THEN    (* 3 拍 = DebounceTime 的周期化替代 *)
        debounceCount := debounceCount + 1;
    END_IF
    (* R1: 连续 3 拍为 TRUE 才认可粘度条件 *)
    IF debounceCount >= 3 THEN
        viscosityValid := TRUE;
    END_IF
ELSE
    (* R1: 输入一 FALSE 立即失效，不等计数下滑 *)
    debounceCount := 0;
    viscosityValid := FALSE;
END_IF

(* R2: 只有在急停回路正常且粘度条件有效时才允许驱动 *)
VFD_RUN := PASTE_E_STOP_NC AND viscosityValid;

(* R3: 只在 VFD_RUN 为 TRUE 的拍累计；停机时保持（不写就是保持）。 *)
IF VFD_RUN THEN
    runHours := runHours + 1;
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + 1;
END_IF

(* R4: 达到 500 小时置维护提示；它只是指示，不参与 R2 的允许条件。 *)
IF runHours >= 500 THEN
    PUMP_MAINT_DUE := TRUE;
END_IF

END_FUNCTION_BLOCK
