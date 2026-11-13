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
    prevResetBtn      : BOOL := FALSE;
    localResetRising  : BOOL;
    localDataFault    : BOOL;
    localQualified    : BOOL;
    tmpFuelInc        : LREAL;
    tmpQualInc        : LREAL;
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
Units/boundaries:
  scanSeconds: >0 (exclusive) and ≤10 (inclusive); unit s.
  steamFlow: [0,90] kg/s; fuelFlow: [0,6] kg/s.
  Conversion: kg/s × s ÷ 1000 = t.
  Prices: steam 280 元/t; fuel 1500 元/t.
================================================================================
*)
BEGIN
    (* Edge detection for reset (PUB012) *)
    localResetRising := resetBtn AND NOT prevResetBtn;

    (* Fault detection (PUB008) *)
    localDataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
                      OR (steamFlow < 0.0) OR (steamFlow > 90.0)
                      OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

    (* Qualified flag — closed interval (PUB006) *)
    localQualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
                      AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

    (* Accumulation: reset takes priority (PUB009, PUB002) *)
    IF localResetRising THEN
        qualifiedTon := 0.0;
        fuelTon      := 0.0;
    ELSIF enable AND NOT localDataFault THEN
        (* PUB007: fuelTon increments regardless of qualified status *)
        tmpFuelInc := fuelFlow * scanSeconds / 1000.0;
        fuelTon := fuelTon + tmpFuelInc;

        (* PUB003, PUB005: qualifiedTon increments only when qualified=TRUE *)
        IF localQualified THEN
            tmpQualInc := steamFlow * scanSeconds / 1000.0;
            qualifiedTon := qualifiedTon + tmpQualInc;
        END_IF;
    END_IF;

    (* Monetary calculations every scan (PUB010) *)
    revenue   := qualifiedTon * 280.0;
    cost      := fuelTon * 1500.0;
    netProfit := revenue - cost;

    (* Assign public outputs *)
    qualified    := localQualified;
    dataFault    := localDataFault;

    (* Update edge-detection memory for next scan (PUB012) *)
    prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)