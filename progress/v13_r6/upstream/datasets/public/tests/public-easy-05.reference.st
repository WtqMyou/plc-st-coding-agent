(* 公开题 public-easy-05：Weld Gap Alarm and Startup Inhibition
   平台偏差（契约 §7，2026-10-24 实测）：TIME 字面量恒为 0、TIME 加减恒为 0，
   DebounceTime 没有数值信息量。本题改用**扫描周期计数**：
     * 5 秒上电抑制期 → 5 个扫描周期（1 拍 = 1 s）；
     * 去抖 DebounceTime → 连续 3 个扫描周期（1 拍 = 1 个单位）。
   用例按周期数断言，偏差在用例 note 与回报里写明。
   解释口径（需求未逐字规定，这里显式写清）：抑制期从"上电首拍"起按拍数计满
   5 拍，急停**不重置**这 5 拍（急停的后果按 R4 只要求报警立即 FALSE 与去抖清零，
   见 R4 代码位置），因此 Weld_Soft_Start_Active 严格只表示上电抑制期（R5）。 *)
FUNCTION_BLOCK FB_WeldGapAlarm
VAR_INPUT
    Gap_Exceeded : BOOL;
    Weld_E_Stop_NC : BOOL;
    DebounceTime : TIME;   (* 平台恒为 0，见文件头偏差说明 *)
END_VAR
VAR_OUTPUT
    Operator_Alert : BOOL;
    Weld_Soft_Start_Active : BOOL;
END_VAR
VAR
    initCount : INT;      (* 上电后已过的拍数，5 拍为抑制期 *)
    debounceCount : INT;  (* 间隙超差连续有效拍数 *)
    initialized : BOOL;   (* 上电首拍标志 *)
END_VAR

(* R2/R5: 上电首拍显式初始化：报警灭、抑制期指示 ON、去抖清零 *)
IF NOT initialized THEN
    initialized := TRUE;
    Operator_Alert := FALSE;
    Weld_Soft_Start_Active := TRUE;
    initCount := 0;
    debounceCount := 0;
END_IF

(* R4: 急停优先于初始化与正常监视——放在最前面，
   即使上一拍已经报警，本拍也要立刻熄灭，并清掉不完整的去抖计数。 *)
IF NOT Weld_E_Stop_NC THEN
    Operator_Alert := FALSE;
    debounceCount := 0;
END_IF

IF initCount < 5 THEN
    (* R2: 上电抑制期（5 拍）：报警屏蔽、软启动指示 ON、去抖**不累计**。
       注意这里不是在"计时"，而是数拍；每拍自增一次。 *)
    initCount := initCount + 1;
    Weld_Soft_Start_Active := TRUE;
    debounceCount := 0;
    Operator_Alert := FALSE;
ELSE
    (* R3: 抑制期结束，恢复间隙监视 *)
    Weld_Soft_Start_Active := FALSE;
    IF Weld_E_Stop_NC THEN
        IF Gap_Exceeded THEN
            (* R3: 连续 3 拍超差才报警（代替 DebounceTime） *)
            IF debounceCount < 3 THEN
                debounceCount := debounceCount + 1;
            END_IF
            IF debounceCount >= 3 THEN
                Operator_Alert := TRUE;
            END_IF
        ELSE
            (* R3: 信号一 FALSE 就熄报警并清去抖 *)
            debounceCount := 0;
            Operator_Alert := FALSE;
        END_IF
    END_IF
END_IF

END_FUNCTION_BLOCK
