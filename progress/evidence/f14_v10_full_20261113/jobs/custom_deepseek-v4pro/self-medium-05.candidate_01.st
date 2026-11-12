(* ENGINEERING_CONTRACT
  qualified: combinational; TRUE when steamTemp in [447.0,453.0] and steamPressure in [3750.0,3850.0] (closed intervals) (PUB001,PUB004,S1).
  dataFault: combinational; TRUE when scanSeconds<=0 or >10, steamFlow<0 or >90, fuelFlow<0 or >6 (PUB003,PUB004,S4).
  qualifiedTon/fuelTon: retained accumulators; reset to 0 only on rising resetBtn; no accumulation on the reset scan (PUB004,PUB006,PUB007,S3,S9).
  With no reset edge and enable=TRUE and no dataFault: fuelTon increases; qualifiedTon increases only when qualified (PUB001,PUB002,PUB005,N10-S11,N10-S12).
  With no reset edge and enable=FALSE or dataFault=TRUE: accumulators hold their previous values (PUB006,S5,S6).
  revenue/cost/netProfit: recomputed every scan from current accumulators (PUB005,PUB008,S7).
  Units: flows kg/s, scanSeconds s, ton = kg/1000, revenue 280 CNY/t, cost 1500 CNY/t (PUB001,PUB008).
  resetBtn held TRUE after its edge does not repeatedly reset; only a new rising edge resets (PUB006,PUB007).
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    resetBtn : BOOL;
    scanSeconds : LREAL;
    steamFlow : LREAL;
    fuelFlow : LREAL;
    steamTemp : LREAL;
    steamPressure : LREAL;
END_VAR
VAR_OUTPUT
    qualified : BOOL;
    dataFault : BOOL;
    qualifiedTon : LREAL;
    fuelTon : LREAL;
    revenue : LREAL;
    cost : LREAL;
    netProfit : LREAL;
END_VAR
VAR
    tmp_prev_reset : BOOL;
    tmp_reset_rise : BOOL;
    tmp_qualified_ton : LREAL;
    tmp_fuel_ton : LREAL;
END_VAR

    tmp_reset_rise := resetBtn AND NOT tmp_prev_reset;

    dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
                 OR (steamFlow < 0.0) OR (steamFlow > 90.0)
                 OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

    qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
                 AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

    IF tmp_reset_rise THEN
        tmp_qualified_ton := 0.0;
        tmp_fuel_ton := 0.0;
    ELSIF enable AND NOT dataFault THEN
        tmp_fuel_ton := tmp_fuel_ton + ((fuelFlow * scanSeconds) / 1000.0);
        IF qualified THEN
            tmp_qualified_ton := tmp_qualified_ton + ((steamFlow * scanSeconds) / 1000.0);
        END_IF;
    END_IF;

    tmp_prev_reset := resetBtn;

    qualifiedTon := tmp_qualified_ton;
    fuelTon := tmp_fuel_ton;
    revenue := tmp_qualified_ton * 280.0;
    cost := tmp_fuel_ton * 1500.0;
    netProfit := revenue - cost;

END_FUNCTION_BLOCK