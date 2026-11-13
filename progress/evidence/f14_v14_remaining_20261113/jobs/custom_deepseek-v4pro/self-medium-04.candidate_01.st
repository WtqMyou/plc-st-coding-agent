(* ENGINEERING_CONTRACT
- valveOpen: set TRUE only by start edge from idle/pending; held while filling below target; set FALSE same scan when accum>=target or reset edge. Same-scan reset priority over start/flow/confirm. S2,S7,S8,S9,S12,S13.
- fillsToday: increments once only when local_pending AND doneSensor; reset edge zeroes same scan; saturates at 32767 while still clearing local_pending. S1,S3,S4,S6,S10,S11,S14.
- local_pending: set when threshold reached; cleared by confirm, reset, or start-new-bottle cancellation. S4,S10,S11,S13,S14.
- local_accum: cleared by reset/start; adds flowVol only while local_filling including start scan; compare >= targetVol. S5,S8,S12.
- local_filling: filling process state; start edge activates; threshold/reset deactivates.
- Edge memory false before first call; doneSensor read as level. Units: volume REAL mL, count INT max 32767.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    resetBtn : BOOL;
    doneSensor : BOOL;
    targetVol : REAL;
    flowVol : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL := FALSE;
    fillsToday : INT := 0;
END_VAR
VAR
    tmp_prevStart : BOOL := FALSE;
    tmp_prevReset : BOOL := FALSE;
    local_accum : REAL := 0.0;
    local_filling : BOOL := FALSE;
    local_pending : BOOL := FALSE;
    local_startR : BOOL;
    local_resetR : BOOL;
END_VAR

local_startR := startBtn AND (NOT tmp_prevStart);
local_resetR := resetBtn AND (NOT tmp_prevReset);

IF local_resetR THEN
    valveOpen := FALSE;
    fillsToday := 0;
    local_accum := 0.0;
    local_filling := FALSE;
    local_pending := FALSE;
ELSE
    IF local_startR AND (NOT local_filling) THEN
        local_pending := FALSE;
        local_filling := TRUE;
        valveOpen := TRUE;
        local_accum := 0.0;
    END_IF;

    IF local_filling THEN
        local_accum := local_accum + flowVol;
        IF local_accum >= targetVol THEN
            local_filling := FALSE;
            valveOpen := FALSE;
            local_pending := TRUE;
        END_IF;
    END_IF;

    IF local_pending AND doneSensor THEN
        IF fillsToday < 32767 THEN
            fillsToday := fillsToday + 1;
        END_IF;
        local_pending := FALSE;
    END_IF;
END_IF;

tmp_prevStart := startBtn;
tmp_prevReset := resetBtn;
END_FUNCTION_BLOCK