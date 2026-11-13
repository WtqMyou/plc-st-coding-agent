(* ENGINEERING_CONTRACT: Steam Header Overpressure Interlock + Fault Diagnosis
 * ================================================================================
 * [PUB001] Function: FB - steam header overpressure interlock with fault footprint
 * [PUB002] Trip activation: runRequest AND (NOT pressureValid OR pressure >= 4500.0) same-scan
 * [PUB003] Reset permission: resetBtn rising-edge AND NOT runRequest AND pressureValid AND pressure <= 4200.0
 * [PUB004] Hysteresis: 300 kPa (4500 trip / 4200 reset gap per PUB003/PUB010)
 * [PUB005] Fault bit0=1: runRequest AND NOT pressureValid (transmitter failure)
 * [PUB006] Fault bit1=2: outletCmd>=50 AND outletFeedback<=10 for 3 consecutive valid overpressure scans
 *            Counter reset on: NOT runRequest, NOT pressureValid, pressure<4500, or condition unsatisfied
 * [PUB007] Fault bit2=4: fuelFlow >= 4.0 AND steamFlow <= 10.0 (valid overpressure工况 only)
 * [PUB008] Fault bit3=8: overpressure but no specific cause identified (valid overpressure工况 only)
 * [PUB009] currentCauseMask reset to 0 when NOT runRequest; low 4 bits only; allowed: 0,1,2,4,6,8
 * [PUB010] latchedCauseMask: bitwise OR accumulation while tripLatched=TRUE; cleared on valid reset only
 * [PUB011] fuelPermit = runRequest AND NOT tripLatched; diagnosticActive = currentCauseMask <> 0
 * [PUB012] Output retention: tripLatched holds until valid reset; fuelPermit combinational per PUB011
 * [PUB013] Units: kPa (pressure), t/h (flow), % (valve), dimensionless (bit masks)
 * [PUB014] No hidden timers; all state in VAR; same-scan evaluation per PUB002
 *
 * CONTRACT_RULES [{"kind":"hold_until_reset","output":"tripLatched","set_input":"runRequest","reset_input":"resetBtn"}]
 *)
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
    stuckCnt        : INT  := 0;
END_VAR

// ---- Rising-edge detection for reset button ----
IF resetBtn AND NOT prevResetBtn THEN
    // Rising edge of resetBtn
    IF NOT runRequest AND pressureValid AND pressure <= 4200.0 THEN
        tripLatched     := FALSE;
        latchedCauseMask := 0;
    END_IF;
END_IF;
prevResetBtn := resetBtn;

// ---- Trip latch activation (PUB002) ----
IF runRequest AND (NOT pressureValid OR pressure >= 4500.0) THEN
    tripLatched := TRUE;
END_IF;

// ---- Fault diagnosis: currentCauseMask (PUB005-PUB009) ----
VAR tempMask : WORD := 0; END_VAR
// bit0: transmitter failure (overrides all other conditions per PUB012)
IF runRequest AND NOT pressureValid THEN
    tempMask := 1; // bit0=1
ELSE
    // bit1 and bit2 only evaluated in valid overpressure工况 (PUB008/PUB009)
    IF runRequest AND pressureValid AND pressure >= 4500.0 THEN
        // Stuck valve counter: 3 consecutive valid scans (PUB006)
        IF outletCmd >= 50 AND outletFeedback <= 10 THEN
            stuckCnt := stuckCnt + 1;
        ELSE
            stuckCnt := 0;
        END_IF;
        IF stuckCnt >= 3 THEN
            tempMask := tempMask OR 2; // bit1=2
        END_IF;
        // Excess combustion: fuelFlow>=4.0 AND steamFlow<=10.0 (PUB007)
        IF fuelFlow >= 4.0 AND steamFlow <= 10.0 THEN
            tempMask := tempMask OR 4; // bit2=4
        END_IF;
        // Unlocated: overpressure but no specific cause (PUB008)
        IF tempMask = 0 THEN
            tempMask := 8; // bit3=8
        END_IF;
    ELSE
        stuckCnt := 0;
    END_IF;
ELSE
    stuckCnt := 0;
END_IF;
currentCauseMask := tempMask;

// ---- Latched cause accumulation (PUB010) ----
IF tripLatched THEN
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
END_IF;

// ---- Fuel permit and diagnostic (PUB011) ----
fuelPermit      := runRequest AND NOT tripLatched;
diagnosticActive := currentCauseMask <> 0;

// ---- Update previous run state for rising-edge tracking ----
prevRunRequest := runRequest;
END_FUNCTION_BLOCK