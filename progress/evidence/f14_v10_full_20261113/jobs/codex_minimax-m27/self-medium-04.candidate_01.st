(* ENGINEERING_CONTRACT
 * Filling Valve Controller - Discrete Scan State Machine
 * 
 * | State            | Activation           | Retention           | Explicit Reset       | Same-scan Priority | Units/Boundaries     |
 * |------------------|----------------------|---------------------|----------------------|--------------------|----------------------|
 * | valveOpen=FALSE  | resetBtn rising      | N/A (output only)   | N/A                  | highest            | BOOL                 |
 * | valveOpen=TRUE   | rising(startBtn) & !prev(valveOpen) | while accVol < targetVol | resetBtn rising | 2nd            | accumulated REAL [0, ∞) |
 * | pendingFill=TRUE | valve closes (accVol>=target) | until doneSensor=TRUE OR new start OR reset | resetBtn rising | 3rd            | BOOL internal state       |
 * | fillsToday++     | doneSensor=TRUE & pendingFill | N/A (output only)  | resetBtn rising      | lowest             | INT [0..32767]           |
 *
 * PUB002: startBtn rising edge detection uses prevStartBtn
 * PUB003: resetBtn rising edge detection uses prevResetBtn
 * PUB004: doneSensor read as level each scan (PUB004)
 * PUB005: flowVol added each scan including start scan
 * PUB006: accumulated >= targetVol triggers valve close same scan
 * PUB007: doneSensor checked immediately after valve close
 * PUB008: if doneSensor=TRUE same scan, confirm and clear pendingFill
 * PUB009: if doneSensor=FALSE, pendingFill retained for later confirmation
 * PUB010: fillsToday increments by 1 per confirmation
 * PUB011: fillsToday saturates at 32767
 * PUB012: resetBtn rising clears all state (valveOpen, accumulatedVol, pendingFill, fillsToday)
 * PUB035: new start cancels pendingFill immediately
 * PUB043: continuous doneSensor=TRUE does not double-count
 *)
FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    resetBtn    : BOOL;
    doneSensor  : BOOL;
    targetVol   : REAL;
    flowVol     : REAL;
END_VAR
VAR_OUTPUT
    valveOpen   : BOOL := FALSE;
    fillsToday  : INT  := 0;
END_VAR
VAR
    prevStartBtn    : BOOL := FALSE;
    prevResetBtn    : BOOL := FALSE;
    accumulatedVol  : REAL := 0.0;
    pendingFill     : BOOL := FALSE;
END_VAR

    // Priority 1: Reset clears everything, no other action this scan
    IF resetBtn AND NOT prevResetBtn THEN
        valveOpen       := FALSE;
        accumulatedVol  := 0.0;
        pendingFill     := FALSE;
        fillsToday      := 0;
        prevStartBtn    := startBtn;
        prevResetBtn    := resetBtn;
        RETURN;
    END_IF;

    // Priority 2: Start new bottle (clears any pending confirmation)
    IF startBtn AND NOT prevStartBtn THEN
        pendingFill    := FALSE;
        accumulatedVol := 0.0;
        valveOpen      := TRUE;
        // flowVol added in filling section below
    END_IF;

    // Priority 3: Filling state - accumulate flow and check target
    IF valveOpen THEN
        accumulatedVol := accumulatedVol + flowVol;
        IF accumulatedVol >= targetVol THEN
            valveOpen := FALSE;
            // Immediate doneSensor check after valve close
            IF doneSensor THEN
                pendingFill := FALSE;
                IF fillsToday < 32767 THEN
                    fillsToday := fillsToday + 1;
                END_IF;
            ELSE
                pendingFill := TRUE;
            END_IF;
        END_IF;
    END_IF;

    // Priority 4: Pending confirmation - wait for doneSensor
    IF pendingFill AND doneSensor THEN
        pendingFill := FALSE;
        IF fillsToday < 32767 THEN
            fillsToday := fillsToday + 1;
        END_IF;
    END_IF;

    prevStartBtn := startBtn;
    prevResetBtn := resetBtn;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)