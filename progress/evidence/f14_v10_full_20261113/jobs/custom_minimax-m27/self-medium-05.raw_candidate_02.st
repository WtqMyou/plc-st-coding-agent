FUNCTION_BLOCK FB
VAR_INPUT
    enable        : BOOL;
    resetBtn      : BOOL;
    scanSeconds   : LREAL;
    steamFlow     : LREAL;
    fuelFlow      : LREAL;
    steamTemp     : LREAL;
    steamPressure : LREAL;
END_VAR
VAR_OUTPUT
    qualified    : BOOL;
    dataFault    : BOOL;
    qualifiedTon : LREAL;
    fuelTon      : LREAL;
    revenue      : LREAL;
    cost         : LREAL;
    netProfit    : LREAL;
END_VAR
VAR
    prevResetBtn     : BOOL := FALSE;
    tmpResetRising   : BOOL;
    tmpDataFault     : BOOL;
    tmpQualified     : BOOL;
    tmpFuelIncrement : LREAL;
    tmpQualIncrement : LREAL;
END_VAR
(*
ENGINEERING_CONTRACT
================================================================================
 PUB001: enable=TRUE → metering active; FALSE → hold accumulators (unless reset).
 PUB002: resetBtn rising edge → immediate zero-clear of qualifiedTon & fuelTon.
 PUB003: qualifiedTon, fuelTon accumulate in t (kg/s × s ÷ 1000); revenue=ton×280.
 PUB005: qualifiedTon increment requires qualified flag TRUE (see PUB001).
 PUB006: closed-interval qualification: temp∈[447,453] AND press∈[3750,3850].
 PUB007: fuelTon always accumulates when enable=TRUE AND no fault (independent of qualified).
 PUB008: dataFault when scanSeconds≤0 OR scanSeconds>10 OR flow out of [0,90]/[0,6].
 PUB009: reset rising edge PRIOR to fault freeze; both accumulators = 0.0 same-scan.
 PUB010: revenue/cost/netProfit update every scan (even when accumulation frozen).
 PUB011: qualifiedTon, fuelTon, revenue, cost ≥ 0 always; netProfit may be negative.
 PUB012: reset is edge-triggered (prevBtn memory); level-hold has no effect.
 PUB013–PUB016: scanSeconds, steamFlow, fuelFlow numeric bounds; fault gates accumulation.
================================================================================
Output states:
  qualified    | activation: steamTemp∈[447,453] ∧ steamPressure∈[3750,3850]; RETAINED.
  dataFault    | activation: scanSeconds≤0 ∨ scanSeconds>10 ∨ steamFlow∉[0,90] ∨ fuelFlow∉[0,6]; RETAINED.
  qualifiedTon | hold_until_reset: cleared on resetBtn rising edge; no other reset.
  fuelTon      | hold_until_reset: cleared on resetBtn rising edge; no other reset.
  revenue/cost/netProfit | computed every scan from accumulator values; not independently latched.
================================================================================
*)
BEGIN
    tmpResetRising := resetBtn AND NOT prevResetBtn;
    tmpDataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
                    OR (steamFlow < 0.0) OR (steamFlow > 90.0)
                    OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);
    tmpQualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
                    AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

    IF tmpResetRising THEN
        qualifiedTon := 0.0;
        fuelTon := 0.0;
    ELSIF enable AND NOT tmpDataFault THEN
        tmpFuelIncrement := fuelFlow * scanSeconds / 1000.0;
        fuelTon := fuelTon + tmpFuelIncrement;
        IF tmpQualified THEN
            tmpQualIncrement := steamFlow * scanSeconds / 1000.0;
            qualifiedTon := qualifiedTon + tmpQualIncrement;
        END_IF;
    END_IF;

    revenue := qualifiedTon * 280.0;
    cost := fuelTon * 1500.0;
    netProfit := revenue - cost;

    qualified := tmpQualified;
    dataFault := tmpDataFault;

    prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)