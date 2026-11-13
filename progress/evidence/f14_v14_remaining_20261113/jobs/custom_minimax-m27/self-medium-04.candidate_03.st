FUNCTION_BLOCK FB
VAR_INPUT
    startBtn  : BOOL;
    resetBtn  : BOOL;
    doneSensor: BOOL;
    targetVol : REAL;
    flowVol   : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;
    fillsToday: INT;
END_VAR
VAR
    state           : INT;        // 0=IDLE, 1=FILLING, 2=PENDING
    prev_startBtn   : BOOL := FALSE;
    prev_resetBtn   : BOOL := FALSE;
    prev_valveOpen  : BOOL := FALSE;
    pendingConfirm  : BOOL;
    accumulatedVol  : REAL := 0.0;
END_VAR

// ENGINEERING_CONTRACT
// States: IDLE(0), FILLING(1), PENDING(2)
// Outputs: valveOpen (BOOL, hold open during FILLING until target reached or reset)
//          fillsToday (INT, hold-until-confirm count, saturation at 32767)
// Confirmed fills increment fillsToday by 1 per bottle, cleared on reset
// ResetBtn rising edge has absolute priority; clears all state and closes valve
// StartBtn rising edge in IDLE or PENDING starts new bottle, cancels pending
// Confirmation checks doneSensor at valve-close scan; clears pendingConfirm after
// No hidden timers; all state in VAR; explicit edge detection via prev_* vars

(* CONTRACT_RULES [] *)

// PUB001: Reset takes priority - ignore everything else this scan
IF resetBtn AND NOT prev_resetBtn THEN
    pendingConfirm := FALSE;
    accumulatedVol := 0.0;
    valveOpen      := FALSE;
    fillsToday     := 0;
    state          := 0;
    prev_startBtn  := resetBtn;
    prev_resetBtn  := resetBtn;
    prev_valveOpen := valveOpen;
    RETURN;
END_IF;

// PUB002/PUB047: Start new bottle when startBtn rises (idle or waiting confirmation)
IF startBtn AND NOT prev_startBtn AND (state = 0 OR state = 2) THEN
    state          := 1;          // FILLING
    pendingConfirm := FALSE;      // cancel previous pending if any
    accumulatedVol := flowVol;    // PUB008: start scan counts flow
    IF accumulatedVol >= targetVol THEN
        valveOpen := FALSE;        // PUB014: immediate达标 close
        IF doneSensor THEN
            IF fillsToday < 32767 THEN
                fillsToday := fillsToday + 1; // PUB030/PUB031: confirm new bottle
            END_IF;
            pendingConfirm := FALSE;
            state := 0;            // back to idle
        ELSE
            pendingConfirm := TRUE;
            state := 2;            // PENDING
        END_IF;
    ELSE
        valveOpen := TRUE;
    END_IF;
    prev_startBtn  := startBtn;
    prev_resetBtn  := resetBtn;
    prev_valveOpen := valveOpen;
    RETURN;
END_IF;

// PUB003: Accumulate flow during filling, including start scan
IF state = 1 THEN
    accumulatedVol := accumulatedVol + flowVol;
    IF accumulatedVol >= targetVol THEN
        valveOpen := FALSE;
        accumulatedVol := targetVol; // PUB035: cap at target
        pendingConfirm := TRUE;
        IF doneSensor THEN
            // PUB014/PUB004: 本拍关阀后立即确认
            IF fillsToday < 32767 THEN
                fillsToday := fillsToday + 1;
            END_IF;
            pendingConfirm := FALSE;
            state := 0;
        ELSE
            state := 2; // PUB004: wait for future TRUE
        END_IF;
    END_IF;
END_IF;

// PUB004: In PENDING, confirm on first TRUE of doneSensor (unless reset/start)
IF state = 2 AND doneSensor THEN
    IF fillsToday < 32767 THEN
        fillsToday := fillsToday + 1;
    END_IF;
    pendingConfirm := FALSE;
    state := 0;
END_IF;

prev_startBtn  := startBtn;
prev_resetBtn  := resetBtn;
prev_valveOpen := valveOpen;
END_FUNCTION_BLOCK