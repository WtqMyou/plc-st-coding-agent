(* ENGINEERING_CONTRACT *)
(*
PUB001-PUB005: State machine (idle/filling/pending)
- valveOpen: active in filling, reset clears it, held until target reached
- fillsToday: monotonic up, reset to 0, saturates at 32767
- pendingConfirm: set when valve closes without immediate doneSensor, cleared on confirmation or reset

PUB006: startBtn rising edge triggers new bottle (only in idle or pending)
PUB007: resetBtn rising edge takes absolute priority, clears all state
PUB008: doneSensor level-triggered confirmation (checked after valve state set)
PUB009-PUB011: flowVol accumulated per scan in tmp_accVol; start scan includes its own flowVol
PUB012-PUB016: saturation behavior, no repeat count, no count while filling
*)
(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    startBtn   : BOOL;
    resetBtn   : BOOL;
    doneSensor : BOOL;
    targetVol  : REAL;
    flowVol    : REAL;
END_VAR
VAR_OUTPUT
    valveOpen  : BOOL;
    fillsToday : INT;
END_VAR
VAR
    state           : INT;       // 0=idle, 1=filling, 2=pendingConfirm
    tmp_accVol      : REAL;      // accumulated volume for current bottle
    tmp_pending     : BOOL;      // bottle waiting for doneSensor confirmation
    prev_startBtn   : BOOL;      // previous scan startBtn (power-on FALSE)
    prev_resetBtn   : BOOL;      // previous scan resetBtn (power-on FALSE)
    tmp_risingStart : BOOL;
    tmp_risingReset : BOOL;
END_VAR

// Rising edge detection
tmp_risingStart := startBtn AND NOT prev_startBtn;
tmp_risingReset := resetBtn AND NOT prev_resetBtn;

// Update previous values
prev_startBtn := startBtn;
prev_resetBtn := resetBtn;

// State machine
IF tmp_risingReset THEN
    fillsToday := 0;
    valveOpen := FALSE;
    tmp_pending := FALSE;
    tmp_accVol := 0.0;
    state := 0;
ELSE
    CASE state OF
        0: // idle
            IF tmp_risingStart THEN
                IF tmp_pending THEN
                    tmp_pending := FALSE;
                END_IF;
                tmp_accVol := flowVol;
                IF flowVol >= targetVol THEN
                    valveOpen := FALSE;
                    tmp_pending := TRUE;
                    state := 2;
                ELSE
                    valveOpen := TRUE;
                    state := 1;
                END_IF;
            END_IF;

        1: // filling
            tmp_accVol := tmp_accVol + flowVol;
            IF tmp_accVol >= targetVol THEN
                valveOpen := FALSE;
                tmp_pending := TRUE;
                state := 2;
            END_IF;

        2: // pendingConfirm
            IF tmp_risingStart THEN
                IF tmp_pending THEN
                    tmp_pending := FALSE;
                END_IF;
                tmp_accVol := flowVol;
                IF flowVol >= targetVol THEN
                    valveOpen := FALSE;
                    tmp_pending := TRUE;
                ELSE
                    valveOpen := TRUE;
                    state := 1;
                END_IF;
            ELSIF doneSensor THEN
                IF fillsToday < 32767 THEN
                    fillsToday := fillsToday + 1;
                END_IF;
                tmp_pending := FALSE;
                state := 0;
            END_IF;
    END_CASE;
END_IF;

END_FUNCTION_BLOCK