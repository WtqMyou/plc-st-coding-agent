(* ENGINEERING_CONTRACT FB_SteamAccumulator
   ┌──────────────┬─────────────────────┬──────────────────────┬───────────────┬─────────────┐
   │ Output       │ Activation          │ Retention            │ Reset/Deact   │ Boundaries  │
   ├──────────────┼─────────────────────┼──────────────────────┼───────────────┼─────────────┤
   │ qualified    │ enable, no fault    │ N/A (combinational)  │ N/A           │ T∈[447,453] │
   │              │                     │                      │               │ P∈[3750,3850]│
   │ dataFault    │ scanSeconds/flow    │ N/A (combinational)  │ N/A           │ dt∈(0,10]   │
   │              │                     │                      │               │ SF∈[0,90]   │
   │              │                     │                      │               │ FF∈[0,6]    │
   │ qualifiedTon │ enable∧no fault∧    │ Hold value on        │ resetBtn↑     │ ≥0, t units │
   │              │ qualified (additive)│ disable/fault/hold   │ clears to 0   │             │
   │ fuelTon      │ enable∧no fault     │ Hold value on        │ resetBtn↑     │ ≥0, t units │
   │              │ (always add)        │ disable/fault/hold   │ clears to 0   │             │
   │ revenue      │ Always updated      │ N/A                  │ N/A           │ ≥0, yuan    │
   │ cost         │ Always updated      │ N/A                  │ N/A           │ ≥0, yuan    │
   │ netProfit    │ Always updated      │ N/A                  │ N/A           │ ±, yuan     │
   └──────────────┴─────────────────────┴──────────────────────┴───────────────┴─────────────┘
   [PUB001] qualified := steamTemp∈[447,453] ∧ steamPressure∈[3750,3850] (closed interval)
   [PUB002] qualifiedTon accumulates when enable∧no fault∧qualified (kg/s×s/1000→t)
   [PUB003] fuelTon always accumulates when enable∧no fault (kg/s×s/1000→t)
   [PUB004] dataFault := scanSeconds≤0 ∨ scanSeconds>10 ∨ steamFlow∉[0,90] ∨ fuelFlow∉[0,6]
   [PUB005] resetBtn↑ → immediate zero, no accumulation in same scan (edge, not level)
   [PUB006] resetBtn↑ takes priority over dataFault; both may report simultaneously
   [PUB007] revenue=qualifiedTon×280, cost=fuelTon×1500, netProfit=revenue-cost (per-scan)
   [PUB008] qualifiedTon/fuelTon/revenue/cost ≥ 0; netProfit may be negative
   [PUB009] No hidden timers; static VAR for state; R_TRIG for edge detection
   [PUB010] same-scan: evaluate final enable/fault before calling accumulation
   [PUB048] Closed-interval qualification; boundary values are QUALIFIED
   [PUB049] ScanSeconds 10.0 is valid; >10.0 is fault
   [PUB050] negative flow values are faults (PUB004 scope)
*)
FUNCTION_BLOCK FB
VAR_INPUT
    enable       : BOOL;
    resetBtn     : BOOL;
    scanSeconds  : LREAL;
    steamFlow    : LREAL;
    fuelFlow     : LREAL;
    steamTemp    : LREAL;
    steamPressure: LREAL;
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
    resetRtrig   : R_TRIG;
    prevResetBtn : BOOL := FALSE;
    tmpFault     : BOOL;
    tmpEnable    : BOOL;
    tmpAddQ      : LREAL;
    tmpAddF      : LREAL;
END_VAR
VAR_TEMP
    incQualified : LREAL;
    incFuel      : LREAL;
END_VAR
(* ── Scan cycle start ──────────────────────────────────────────────── *)
resetRtrig(CLK := resetBtn);
tmpFault  := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
              OR (steamFlow < 0.0) OR (steamFlow > 90.0)
              OR (fuelFlow < 0.0)  OR (fuelFlow > 6.0);
tmpEnable := enable AND NOT tmpFault;

qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
             AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

incQualified := 0.0;
incFuel      := 0.0;

(* Accumulation path: only when no reset rising edge this scan *)
IF NOT resetRtrig.Q THEN
    IF tmpEnable THEN
        incFuel := fuelFlow * scanSeconds / 1000.0;
        IF qualified THEN
            incQualified := steamFlow * scanSeconds / 1000.0;
        END_IF;
    END_IF;
    qualifiedTon := qualifiedTon + incQualified;
    fuelTon      := fuelTon + incFuel;
ELSE
    (* Reset rising edge: cleared, no accumulation this scan *)
    qualifiedTon := 0.0;
    fuelTon      := 0.0;
END_IF;

(* Revenue/cost/netProfit: always updated per scan from current accumulators *)
revenue   := qualifiedTon * 280.0;
cost      := fuelTon * 1500.0;
netProfit := revenue - cost;

dataFault := tmpFault;

prevResetBtn := resetBtn;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)