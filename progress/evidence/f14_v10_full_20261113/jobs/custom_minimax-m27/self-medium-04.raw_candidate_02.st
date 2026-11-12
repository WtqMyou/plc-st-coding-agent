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
    state          : INT := 0;
    accumulated    : REAL := 0.0;
    pendingConfirm : BOOL := FALSE;
    prevStartBtn   : BOOL := FALSE;
    prevResetBtn   : BOOL := FALSE;
    prevValveOpen  : BOOL := FALSE;
END_VAR
BEGIN
    (* ENGINEERING_CONTRACT
    ---------------------------------------------------------------------
    PUB001: Initialization - valve closed (valveOpen=FALSE), no pending
            confirmation (pendingConfirm=FALSE), fillsToday=0 on cold start.
    PUB002: Rising-edge detection for startBtn/resetBtn; pre-power state FALSE.
    PUB003: Scan execution order: reset(1)→start/new-bottle(2)→accumulate/
            close-on-target(3)→doneSensor read→confirm/count(4).
    PUB004: resetBtn rising edge has highest priority; clears all state,
            ignores same-scan start/flow/confirmation.
    PUB005: startBtn rising edge in IDLE(0)/WAIT_CONFIRM(2) starts new bottle,
            clears accumulation, opens valve. Prior pendingConfirm cancelled.
            New start during FILLING(1) does NOT reset current bottle.
    PUB006: Accumulate flowVol every scan including startup scan.
    PUB007: When accumulated >= targetVol, close valve and set pendingConfirm
            immediately in same scan.
    PUB008: After closing, read doneSensor same scan. If TRUE, confirm/count
            immediately. If FALSE, wait for first TRUE (unless reset/new-start).
    PUB009: Each confirmation increments fillsToday by 1. At 32767, confirm
            completes but count stays at 32767.
    PUB010: Confirmation clears pendingConfirm. Continuous TRUE does not
            double-count. New-bottle start-cancel clears pendingConfirm.
    PUB011: fillsToday is INT; reset clears to 0.
    ---------------------------------------------------------------------
    OUTPUT RETENTION:
    - valveOpen: held open during FILLING until target met or reset/start.
    - fillsToday: monotonic non-decreasing except reset (S3); max 32767.
    - pendingConfirm: held TRUE from close until first TRUE doneSensor.
    EXPLICIT RESET: resetBtn rising edge clears accumulated, fillsToday,
            valveOpen, pendingConfirm, state→0(IDLE).
    SAME-SCAN PRIORITY: reset > close-on-target-with-confirm > start.
    UNITS/BOUNDARIES: accumulated REAL mL; fillsToday INT [0..32767];
            targetVol, flowVol REAL mL.
    ---------------------------------------------------------------------
    *)

    // --- Step 1: Reset (highest priority) ---
    IF resetBtn AND NOT prevResetBtn THEN
        accumulated    := 0.0;
        fillsToday     := 0;
        valveOpen      := FALSE;
        pendingConfirm := FALSE;
        state          := 0;
        prevStartBtn   := startBtn;
        prevResetBtn   := resetBtn;
        prevValveOpen  := FALSE;
        RETURN;
    END_IF;

    // --- Step 2: Start new bottle ---
    IF startBtn AND NOT prevStartBtn THEN
        IF state = 2 THEN
            pendingConfirm := FALSE;
        END_IF;
        IF state <> 1 THEN
            accumulated := 0.0;
            valveOpen   := TRUE;
            state       := 1;
        END_IF;
    END_IF;

    // --- Step 3: Accumulate and close on target ---
    IF state = 1 THEN
        accumulated := accumulated + flowVol;
        IF accumulated >= targetVol THEN
            valveOpen      := FALSE;
            pendingConfirm := TRUE;
            state          := 2;
        END_IF;
    END_IF;

    // --- Step 4: Read doneSensor and confirm/count ---
    IF pendingConfirm THEN
        IF doneSensor THEN
            IF fillsToday < 32767 THEN
                fillsToday := fillsToday + 1;
            END_IF;
            pendingConfirm := FALSE;
            state          := 0;
        END_IF;
    END_IF;

    // Update previous states for next scan edge detection
    prevStartBtn  := startBtn;
    prevResetBtn  := resetBtn;
    prevValveOpen := valveOpen;
END_FUNCTION_BLOCK