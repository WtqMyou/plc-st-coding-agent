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
    prevStartBtn   : BOOL := FALSE;
    prevResetBtn   : BOOL := FALSE;
    prevValveOpen  : BOOL := FALSE;
    pendingConfirm : BOOL := FALSE;
    accumulatedVol : REAL := 0.0;
    tmp_risingReset : BOOL;
    tmp_risingStart : BOOL;
    tmp_isFilling   : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   valveOpen: set only on start edge from idle/wait (R2,S2); holds while
             accumulatedVol < targetVol (R3,S9); closes on reset or target reach (R1,R3,S5).
   pendingConfirm: set same scan as target close; persists until confirmation,
             next start, or reset; sensor TRUE does not repeat count (R3-R5,S11).
   fillsToday: increments once on doneSensor with pending; saturates at 32767
             and still clears pending; reset zeros in same scan (R4-R5,S1,S6,S14).
   accumulatedVol: reset on reset/new bottle; adds flowVol only while filling,
             including start scan (R1-R3,S12).
   Priority: reset > start/new-bottle cancellation > flow/threshold close > done confirm.
   Units: targetVol/flowVol in mL REAL; fillsToday signed INT bounds 0..32767.
*)

(* CONTRACT_RULES [] *)

tmp_risingReset := resetBtn AND NOT prevResetBtn;
tmp_risingStart := startBtn AND NOT prevStartBtn;

IF tmp_risingReset THEN
    valveOpen      := FALSE;
    fillsToday     := 0;
    accumulatedVol := 0.0;
    pendingConfirm := FALSE;
ELSE
    tmp_isFilling := FALSE;

    IF tmp_risingStart AND NOT valveOpen THEN
        pendingConfirm := FALSE;
        accumulatedVol := 0.0;
        valveOpen      := TRUE;
        tmp_isFilling   := TRUE;
    ELSIF valveOpen THEN
        tmp_isFilling := TRUE;
    END_IF;

    IF tmp_isFilling THEN
        accumulatedVol := accumulatedVol + flowVol;
        IF accumulatedVol >= targetVol THEN
            valveOpen      := FALSE;
            pendingConfirm := TRUE;
            tmp_isFilling   := FALSE;
        END_IF;
    END_IF;

    IF pendingConfirm AND doneSensor THEN
        IF fillsToday < 32767 THEN
            fillsToday := fillsToday + 1;
        END_IF;
        pendingConfirm := FALSE;
    END_IF;
END_IF;

prevStartBtn  := startBtn;
prevResetBtn  := resetBtn;
prevValveOpen := valveOpen;

END_FUNCTION_BLOCK