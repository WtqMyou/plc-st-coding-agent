(*====================================================================*)
(*  FUNCTION_BLOCK FB                                                *)
(*  Boiler steam‑quality accumulator with fuel consumption, revenue  *)
(*  and net‑profit.  All specifications from the problem statement   *)
(*  are implemented exactly.                                         *)
(*====================================================================*)
FUNCTION_BLOCK FB

VAR_INPUT
    enable       : BOOL;   (*计量使能*)
    resetBtn     : BOOL;   (*清零按钮 – 上升沿有效*)
    scanSeconds  : LREAL;  (*本周期时长 (s) , 合法 0 < dt ≤ 10*)
    steamFlow    : LREAL;  (*蒸汽流量 (kg/s) , 合法 0 … 90*)
    fuelFlow     : LREAL;  (*燃料流量 (kg/s) , 合法 0 … 6*)
    steamTemp    : LREAL;  (*蒸汽温度 (℃)*)
    steamPressure: LREAL;  (*蒸汽压力 (kPa)*)
END_VAR

VAR_OUTPUT
    qualified    : BOOL;   (*本周期蒸汽是否合格*)
    dataFault    : BOOL;   (*数据故障标志*)
    qualifiedTon : LREAL;  (*累计合格蒸汽产量 (t)*)
    fuelTon      : LREAL;  (*累计燃料消耗 (t)*)
    revenue      : LREAL;  (*累计收入 (元)*)
    cost         : LREAL;  (*累计成本 (元)*)
    netProfit    : LREAL;  (*累计净收益 (元) – 允许为负*)
END_VAR

VAR
    prevResetBtn : BOOL := FALSE;   (*上一拍的 resetBtn 状态，用于边沿检测*)
END_VAR

(*------------------------------------------------------------------*)
(*  临时变量，仅用于本周期内部计算                                   *)
VAR_TEMP
    risingReset : BOOL;            (*resetBtn 上升沿标志*)
END_VAR

(*------------------------------------------------------------------*)
(*  1) 上升沿检测                                                   *)
risingReset := resetBtn AND NOT prevResetBtn;

(*------------------------------------------------------------------*)
(*  2) 数据故障判据                                                 *)
dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
             OR (steamFlow < 0.0) OR (steamFlow > 90.0)
             OR (fuelFlow < 0.0)  OR (fuelFlow > 6.0);

(*------------------------------------------------------------------*)
(*  3) 合格判据 (闭区间)                                            *)
qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
             AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

(*------------------------------------------------------------------*)
(*  4) 累计逻辑 – 复位上升沿拥有最高优先级                           *)
IF risingReset THEN
    (* 复位拍：清零且本拍不再累计 *)
    qualifiedTon := 0.0;
    fuelTon      := 0.0;
ELSE
    (* 非复位拍：仅在 enable 且无故障时累计 *)
    IF enable AND NOT dataFault THEN
        (* 燃料消耗 – 只要使能且数据有效即累计 *)
        fuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;

        (* 合格蒸汽产量 – 额外要求本周期蒸汽合格 *)
        IF qualified THEN
            qualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
        END_IF;
    END_IF;
END_IF;

(*------------------------------------------------------------------*)
(*  5) 金额计算 (每拍都更新)                                        *)
revenue   := qualifiedTon * 280.0;   (*元 = t × 280*)
cost      := fuelTon      * 1500.0;  (*元 = t × 1500*)
netProfit := revenue - cost;

(*------------------------------------------------------------------*)
(*  6) 保持非负 (仅作防御性编程，实际运算已保证非负)                 *)
IF qualifiedTon < 0.0 THEN qualifiedTon := 0.0; END_IF;
IF fuelTon      < 0.0 THEN fuelTon      := 0.0; END_IF;
IF revenue      < 0.0 THEN revenue      := 0.0; END_IF;
IF cost         < 0.0 THEN cost         := 0.0; END_IF;

(*------------------------------------------------------------------*)
(*  7) 为下一拍准备边沿检测                                         *)
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK