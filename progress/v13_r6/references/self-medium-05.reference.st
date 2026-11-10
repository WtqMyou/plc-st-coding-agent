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
 prevReset : BOOL;
 qTon : LREAL;
 fTon : LREAL;
END_VAR
qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
 AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);
dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
 OR (steamFlow < 0.0) OR (steamFlow > 90.0)
 OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);
IF resetBtn AND NOT prevReset THEN
 qTon := 0.0;
 fTon := 0.0;
ELSIF enable AND NOT dataFault THEN
 fTon := fTon + fuelFlow * scanSeconds / 1000.0;
 IF qualified THEN
  qTon := qTon + steamFlow * scanSeconds / 1000.0;
 END_IF;
END_IF;
prevReset := resetBtn;
qualifiedTon := qTon;
fuelTon := fTon;
revenue := qTon * 280.0;
cost := fTon * 1500.0;
netProfit := revenue - cost;
END_FUNCTION_BLOCK
