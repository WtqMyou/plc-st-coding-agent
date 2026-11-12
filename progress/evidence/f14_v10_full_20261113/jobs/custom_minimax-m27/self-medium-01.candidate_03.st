(* ENGINEERING_CONTRACT *)
(*
  PUB002/PUB005: valid=FALSE → loadedID:=0, valid=TRUE → loadedID:=recipe[selSlot].recipeID
  PUB006: loadCmd rising-edge triggers one-shot load; level-hold does NOT reload
  PUB007: running=TRUE blocks load, loadedID retains previous value
  PUB008: slot out-of-range [1..8] → valid=FALSE, loadedID unchanged; no array OOB access
  PUB009: validation is conjunction: recipeID<>0 AND totalRatio∈[99.0,101.0] AND temperature∈[30.0,180.0]
  Timing: state retention via VAR (static across scans); first-scan prev_* = FALSE (IEC default)
  S1: !running & rising(loadCmd) & valid-slot & empty-slot → valid=FALSE & loadedID=0
  S4/N10-S4: running → loadedID=prev(loadedID) (includes first production entry)
  N10-S9: !running & !rising(loadCmd) → both outputs retain prev value
*)
(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    recipe      : ARRAY[1..8] OF ST_Recipe;
    selSlot     : INT;
    loadCmd     : BOOL;
    running     : BOOL;
END_VAR
VAR_OUTPUT
    valid       : BOOL;
    loadedID    : INT;
END_VAR
VAR
    tmp_loadTrig  : R_TRIG;
    tmp_prevRunning : BOOL := FALSE;
END_VAR

tmp_loadTrig(CLK := loadCmd);

IF tmp_loadTrig.Q AND NOT running THEN
    IF (selSlot >= 1) AND (selSlot <= 8) THEN
        IF (recipe[selSlot].recipeID <> 0) AND
           (recipe[selSlot].totalRatio >= 99.0) AND (recipe[selSlot].totalRatio <= 101.0) AND
           (recipe[selSlot].temperature >= 30.0) AND (recipe[selSlot].temperature <= 180.0) THEN
            valid    := TRUE;
            loadedID := recipe[selSlot].recipeID;
        ELSE
            valid    := FALSE;
            loadedID := 0;
        END_IF;
    ELSE
        valid    := FALSE;
    END_IF;
ELSIF running THEN
    loadedID := loadedID;
END_IF;

tmp_prevRunning := running;
END_FUNCTION_BLOCK