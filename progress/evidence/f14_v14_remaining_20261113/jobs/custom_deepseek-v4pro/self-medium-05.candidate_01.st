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
    lastResetBtn : BOOL := FALSE;
    tmp_resetRising : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   qualified: combinational per PUB001-S1, ranges closed.
   dataFault: combinational per PUB004, bounds scanSeconds/(0,10], steamFlow [0,90], fuelFlow [0,6].
   qualifiedTon: retained accum; reset on rising resetBtn to 0 same scan; priority over fault/disable.
   fuelTon: retained accum; reset same rising edge; priority over fault/disable.
   revenue/cost/netProfit: derived each scan from tonnage*unit price; money units CNY.
   Reset rising: resetBtn AND NOT lastResetBtn; first TRUE scan counted; held TRUE no repeat.
   Non-negative accum guaranteed by valid inputs and reset; netProfit may be negative.
*)

(* CONTRACT_RULES [] *)

tmp_resetRising := resetBtn AND NOT lastResetBtn;

qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
             AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
             OR (steamFlow < 0.0) OR (steamFlow > 90.0)
             OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

IF tmp_resetRising THEN
    qualifiedTon := 0.0;
    fuelTon := 0.0;
ELSE
    IF enable AND NOT dataFault THEN
        fuelTon := fuelTon + (fuelFlow * scanSeconds / 1000.0);
        IF qualified THEN
            qualifiedTon := qualifiedTon + (steamFlow * scanSeconds / 1000.0);
        END_IF;
    END_IF;
END_IF;

revenue := qualifiedTon * 280.0;
cost := fuelTon * 1500.0;
netProfit := revenue - cost;

lastResetBtn := resetBtn;

END_FUNCTION_BLOCK