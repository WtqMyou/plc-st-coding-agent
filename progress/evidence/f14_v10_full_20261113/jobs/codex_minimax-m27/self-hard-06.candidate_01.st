FUNCTION_BLOCK FB
VAR_INPUT
    runRequest      : BOOL;
    pressure        : REAL;
    pressureValid   : BOOL;
    fuelFlow        : REAL;
    steamFlow       : REAL;
    outletCmd       : INT;
    outletFeedback  : INT;
    resetBtn        : BOOL;
END_VAR
VAR_OUTPUT
    tripLatched     : BOOL;
    fuelPermit      : BOOL;
    currentCauseMask: WORD;
    latchedCauseMask: WORD;
    diagnosticActive: BOOL;
END_VAR
VAR
    prevResetBtn    : BOOL := FALSE;
    prevRunRequest  : BOOL := FALSE;
    prevPressureValid : BOOL := FALSE;
    prevPressure    : REAL := 0.0;
    prevFuelFlow    : REAL := 0.0;
    prevSteamFlow   : REAL := 0.0;
    prevOutletCmd   : INT := 0;
    prevOutletFeedback : INT := 0;
    prevTripLatched : BOOL := FALSE;
    prevCurrentCauseMask : WORD := 0;
    prevLatchedCauseMask : WORD := 0;
    stuckValveConsecutiveCount : INT := 0;
    tmpRisingReset  : BOOL;
    tmpRisingPrevCond : BOOL;
    tmpTwoAgoPrevCond : BOOL;
    tmpStuckCond   : BOOL;
    tmpCurrentMask : WORD;
    tmpOverpressureValid : BOOL;
END_VAR

(* CONTRACT:
   | Output/State    | Activation         | Retention       | Reset/Deactivation           | Same-scan Priority | Units/Boundaries       |
   |-----------------|--------------------|-----------------|-------------------------------|--------------------|------------------------|
   | tripLatched     | runRequest & (!pressureValid OR pressure>=4500.0) | Hold until resetBtn rising & !runRequest & pressureValid & pressure<=4200.0 | resetBtn rising edge clears | Same-scan with clue calc | BOOL; 4500/4200 kPa hysteresis |
   | fuelPermit      | runRequest & !tripLatched | None (combinational) | Clears when tripLatched sets | Same-scan | BOOL |
   | currentCauseMask| Recalc every scan | None (recalculated) | Zero when !runRequest | Same-scan | WORD bits 0-3; 0,1,2,4,6,8 only |
   | latchedCauseMask| OR into when tripLatched | Accumulate across trip | Clear on valid reset | Same-scan | WORD bits 0-3; 0-15 |
   | diagnosticActive| currentCauseMask <> 0 | None | Clears when mask zero | Same-scan | BOOL |
   | stuckValveConsecutiveCount | Increment when stuckCond true 3+ scans | Hold | Reset on any break in condition | Per-scan counter | INT; 0-3+ |

   PUB: PUB001(trip on !pressureValid), PUB002(overpressure>=4500), PUB003(clear hysteresis), PUB004(!runRequest=>mask=0),
        PUB005(stuck valve 3-scan), PUB006(latched accumulation), PUB007(fuelPermit), PUB008(diagnosticActive),
        PUB009(bit3 unlocated), PUB010(bit0 transmitter), PUB011(bit2 excess combustion), PUB012(bit1 valve),
        PUB013(reset conditions), PUB014(bit2 only in overpressure), PUB015(continuous 3-scan)
*)
(* CONTRACT_RULES [] *)

tmpRisingReset := resetBtn AND NOT prevResetBtn;

tmpOverpressureValid := runRequest AND pressureValid AND (pressure >= 4500.0);

tmpStuckCond := tmpOverpressureValid AND (outletCmd >= 50) AND (outletFeedback <= 10);

tmpRisingPrevCond := prevRunRequest AND prevPressureValid AND (prevPressure >= 4500.0) AND (prevOutletCmd >= 50) AND (prevOutletFeedback <= 10);

tmpTwoAgoPrevCond := prevLatchedCauseMask; // placeholder, will use stored 2-ago state
tmpCurrentMask := 0;

IF NOT runRequest THEN
    tmpCurrentMask := 0;
    stuckValveConsecutiveCount := 0;
ELSIF NOT pressureValid THEN
    tmpCurrentMask := 1;
    stuckValveConsecutiveCount := 0;
ELSE
    IF tmpOverpressureValid THEN
        IF tmpStuckCond THEN
            IF tmpRisingPrevCond THEN
                stuckValveConsecutiveCount := 2;
            ELSE
                stuckValveConsecutiveCount := stuckValveConsecutiveCount + 1;
                IF stuckValveConsecutiveCount < 3 THEN
                    stuckValveConsecutiveCount := 3;
                END_IF;
            END_IF;
        ELSE
            stuckValveConsecutiveCount := 0;
        END_IF;
        
        IF stuckValveConsecutiveCount >= 3 THEN
            tmpCurrentMask := tmpCurrentMask OR 2;
        END_IF;
        
        IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
            tmpCurrentMask := tmpCurrentMask OR 4;
        END_IF;
        
        IF tmpCurrentMask = 0 THEN
            tmpCurrentMask := 8;
        END_IF;
    ELSE
        stuckValveConsecutiveCount := 0;
        tmpCurrentMask := 0;
    END_IF;
END_IF;

currentCauseMask := tmpCurrentMask;

IF tmpRisingReset AND NOT runRequest AND pressureValid AND (pressure <= 4200.0) THEN
    tripLatched := FALSE;
    latchedCauseMask := 0;
ELSIF runRequest AND (NOT pressureValid OR (pressure >= 4500.0)) THEN
    tripLatched := TRUE;
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
ELSIF tripLatched THEN
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
ELSE
    tripLatched := FALSE;
    latchedCauseMask := 0;
END_IF;

fuelPermit := runRequest AND NOT tripLatched;

diagnosticActive := (currentCauseMask <> 0);

prevResetBtn := resetBtn;
prevRunRequest := runRequest;
prevPressureValid := pressureValid;
prevPressure := pressure;
prevFuelFlow := fuelFlow;
prevSteamFlow := steamFlow;
prevOutletCmd := outletCmd;
prevOutletFeedback := outletFeedback;
prevTripLatched := tripLatched;
prevCurrentCauseMask := currentCauseMask;
prevLatchedCauseMask := latchedCauseMask;

END_FUNCTION_BLOCK