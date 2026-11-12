FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    resetBtn : BOOL;
    doneSensor : BOOL;
    targetVol : REAL;
    flowVol : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;
    fillsToday : INT;
END_VAR
VAR
    prevStart : BOOL;
    prevReset : BOOL;
    pendingConfirm : BOOL;
    isFilling : BOOL;
    accVolume : REAL;
    tmp_start_edge : BOOL;
    tmp_reset_edge : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
Activation:
- valveOpen opens only on a non-reset start rise from idle/wait-confirm.
- fillsToday increments only after a closed, pending bottle sees doneSensor.
Retention:
- pendingConfirm, isFilling, accVolume and fillsToday persist between scans.
- fillsToday saturates at 32767.
Reset:
- reset rise clears count/volume/pending, closes valve, ignores same-scan start/flow/done.
Same-scan priority:
reset > idle/wait start > flow add and close > done confirmation.
Boundaries:
- volume closes at accVolume >= targetVol; start scan flow is included.
*)

(* CONTRACT_RULES [] *)

tmp_start_edge := startBtn AND NOT prevStart;
tmp_reset_edge := resetBtn AND NOT prevReset;

IF tmp_reset_edge THEN
    fillsToday := 0;
    accVolume := 0.0;
    valveOpen := FALSE;
    pendingConfirm := FALSE;
    isFilling := FALSE;
ELSE
    IF tmp_start_edge AND NOT isFilling THEN
        pendingConfirm := FALSE;
        accVolume := 0.0;
        valveOpen := TRUE;
        isFilling := TRUE;
    END_IF;

    IF isFilling THEN
        accVolume := accVolume + flowVol;
        IF accVolume >= targetVol THEN
            valveOpen := FALSE;
            isFilling := FALSE;
            pendingConfirm := TRUE;
        END_IF;
    END_IF;

    IF pendingConfirm AND doneSensor THEN
        IF fillsToday < 32767 THEN
            fillsToday := fillsToday + 1;
        END_IF;
        pendingConfirm := FALSE;
    END_IF;
END_IF;

prevStart := startBtn;
prevReset := resetBtn;

END_FUNCTION_BLOCK