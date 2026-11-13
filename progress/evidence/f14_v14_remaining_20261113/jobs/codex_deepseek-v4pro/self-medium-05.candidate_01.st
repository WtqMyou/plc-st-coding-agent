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
    local_prev_reset : BOOL := FALSE;
    local_reset_edge : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   - qualified/dataFault: combinational, updated every scan.
   - qualifiedTon: accumulates only when enable, no fault, qualified, and no reset edge.
   - fuelTon: accumulates only when enable, no fault, and no reset edge.
   - resetBtn rising edge: clears both accumulators, higher priority than enable/fault.
   - reset is edge-only; held resetBtn does not repeatedly clear.
   - revenue/cost/netProfit recomputed every scan from current accumulators.
   - scanSeconds unit s, flows kg/s; both are legal under stated fault bounds.
*)

(* CONTRACT_RULES [] *)

local_reset_edge := resetBtn AND NOT local_prev_reset;

qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
             AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

dataFault := (scanSeconds <= 0.0)
             OR (scanSeconds > 10.0)
             OR (steamFlow < 0.0) OR (steamFlow > 90.0)
             OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

IF local_reset_edge THEN
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

local_prev_reset := resetBtn;

END_FUNCTION_BLOCK