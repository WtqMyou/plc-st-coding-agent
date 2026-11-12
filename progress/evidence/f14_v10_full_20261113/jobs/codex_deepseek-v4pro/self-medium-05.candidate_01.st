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
    tmp_PrevReset : BOOL := FALSE;
    tmp_RisingReset : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   qualified: combinational true when steamTemp in [447.0,453.0] AND steamPressure in [3750.0,3850.0], inclusive.
   dataFault: combinational true when scanSeconds<=0.0 or >10.0, steamFlow outside [0.0,90.0], or fuelFlow outside [0.0,6.0].
   qualifiedTon: on reset rising edge -> 0.0 and no accumulation; otherwise add if enable AND !dataFault AND qualified, else hold.
   fuelTon: on reset rising edge -> 0.0 and no accumulation; otherwise add if enable AND !dataFault, else hold.
   revenue, cost, netProfit update every scan from current tonnage; units are t and CNY.
   reset edge has priority over disable and fault; fault flag is still reported.
*)
(* CONTRACT_RULES [] *)

tmp_RisingReset := resetBtn AND NOT tmp_PrevReset;

dataFault := (scanSeconds <= 0.0)
    OR (scanSeconds > 10.0)
    OR (steamFlow < 0.0)
    OR (steamFlow > 90.0)
    OR (fuelFlow < 0.0)
    OR (fuelFlow > 6.0);

qualified := (steamTemp >= 447.0)
    AND (steamTemp <= 453.0)
    AND (steamPressure >= 3750.0)
    AND (steamPressure <= 3850.0);

IF tmp_RisingReset THEN
    qualifiedTon := 0.0;
    fuelTon := 0.0;
ELSE
    IF enable AND NOT dataFault THEN
        fuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;

        IF qualified THEN
            qualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
        END_IF;
    END_IF;
END_IF;

revenue := qualifiedTon * 280.0;
cost := fuelTon * 1500.0;
netProfit := revenue - cost;

tmp_PrevReset := resetBtn;

END_FUNCTION_BLOCK