FUNCTION_BLOCK FB
VAR_INPUT
    enable         : BOOL;
    resetBtn       : BOOL;
    scanSeconds    : LREAL;
    steamFlow      : LREAL;
    fuelFlow       : LREAL;
    steamTemp      : LREAL;
    steamPressure  : LREAL;
END_VAR
VAR_OUTPUT
    qualified      : BOOL;
    dataFault      : BOOL;
    qualifiedTon   : LREAL;
    fuelTon        : LREAL;
    revenue        : LREAL;
    cost           : LREAL;
    netProfit      : LREAL;
END_VAR
VAR
    prevResetBtn   : BOOL := FALSE;
    tmpFuelTon     : LREAL := 0.0;
    tmpQualifiedTon: LREAL := 0.0;
END_VAR

(* ENGINEERING_CONTRACT
 * PUB001-002:   enable=OFF → no accumulation; OFF+FAULT → freeze; reset rising → zero both immediately.
 * PUB003-004:   qualified = (steamTemp∈[447,453] ∧ steamPressure∈[3750,3850]) closed interval.
 * PUB005:       scanSeconds fault: ≤0.0 or >10.0 (10.0 itself is valid).
 * PUB006:       steamFlow fault: <0 or >90; fuelFlow fault: <0 or >6; negative values are faults.
 * PUB007-008:   Accumulation: fuelTon+=fuelFlow×scanSec/1000 when (enable ∧ ¬fault ∧ ¬resetRising).
 * PUB009-010:   Accumulation: qualifiedTon+=steamFlow×scanSec/1000 when (enable ∧ ¬fault ∧ qualified ∧ ¬resetRising).
 * PUB011:       Reset is edge-triggered; hold duration is irrelevant; one rising edge clears once.
 * PUB012-014:   Reset rising has highest priority; same-scan fault is reported but accumulators become 0.
 * PUB015-017:   revenue=qualifiedTon×280, cost=fuelTon×1500, netProfit=revenue−cost; updated every scan.
 * PUB018-022:   qualifiedTon, fuelTon, revenue, cost ≥0 always; netProfit may be negative.
 * Units:        steamFlow/fuelFlow in kg/s, scanSeconds in s → /1000 converts kg→t.
 *)

(* CONTRACT_RULES [] *)

qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
             AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
             OR (steamFlow < 0.0) OR (steamFlow > 90.0)
             OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

IF resetBtn AND NOT prevResetBtn THEN
    tmpQualifiedTon := 0.0;
    tmpFuelTon := 0.0;
ELSE
    tmpQualifiedTon := qualifiedTon;
    tmpFuelTon := fuelTon;
    IF enable AND NOT dataFault THEN
        tmpFuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;
        IF qualified THEN
            tmpQualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
        END_IF;
    END_IF;
END_IF;

qualifiedTon := tmpQualifiedTon;
fuelTon      := tmpFuelTon;

revenue   := qualifiedTon * 280.0;
cost      := fuelTon * 1500.0;
netProfit := revenue - cost;

prevResetBtn := resetBtn;
END_FUNCTION_BLOCK