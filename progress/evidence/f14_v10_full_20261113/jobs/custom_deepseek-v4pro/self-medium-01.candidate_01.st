TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    totalRatio : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE;

(* ENGINEERING_CONTRACT
   valid/loadedID activate only on loadCmd rising edge with running=FALSE (PUB003/PUB007/PUB010).
   Legal slot check 1..8 precedes any array access; out-of-range is not indexed (PUB006/S5).
   Candidate = recipeID<>0 AND totalRatio in [99.0,101.0] AND temperature in [30.0,180.0] (PUB008/N10-S7).
   Accepted invalid edge clears valid=FALSE and loadedID=0; valid edge loads selected recipeID (PUB009/N10-S8/S1).
   running=TRUE overrides any load edge and holds previous valid/loadedID (PUB010/N10-S4/N10-S9).
   No rising edge holds previous outputs (S6/S9).
   Units/bounds: REAL closed intervals; no timing; selSlot dimensionless.
   Conflict note: F13-S1 prose says empty-slot must not change ID, but formal S1/N10-S8/req5 require clear; clear is implemented.
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    recipe : ARRAY[1..8] OF ST_Recipe;
    selSlot : INT;
    loadCmd : BOOL;
    running : BOOL;
END_VAR
VAR_OUTPUT
    valid : BOOL;
    loadedID : INT;
END_VAR
VAR
    tmp_prevLoadCmd : BOOL := FALSE;
    tmp_validState : BOOL := FALSE;
    tmp_loadedIDState : INT := 0;
    tmp_edge : BOOL;
    tmp_slotLegal : BOOL;
    tmp_candidateValid : BOOL;
    tmp_isNonEmpty : BOOL;
    tmp_ratioOk : BOOL;
    tmp_tempOk : BOOL;
    tmp_recipeId : INT;
    tmp_totalRatio : REAL;
    tmp_temperature : REAL;
END_VAR

tmp_edge := loadCmd AND NOT tmp_prevLoadCmd;

IF (NOT running) AND tmp_edge THEN
    tmp_slotLegal := (selSlot >= 1) AND (selSlot <= 8);
    IF tmp_slotLegal THEN
        tmp_recipeId := recipe[selSlot].recipeID;
        tmp_totalRatio := recipe[selSlot].totalRatio;
        tmp_temperature := recipe[selSlot].temperature;

        tmp_isNonEmpty := (tmp_recipeId <> 0);
        tmp_ratioOk := (tmp_totalRatio >= 99.0) AND (tmp_totalRatio <= 101.0);
        tmp_tempOk := (tmp_temperature >= 30.0) AND (tmp_temperature <= 180.0);
        tmp_candidateValid := tmp_isNonEmpty AND tmp_ratioOk AND tmp_tempOk;

        tmp_validState := tmp_candidateValid;
        IF tmp_candidateValid THEN
            tmp_loadedIDState := tmp_recipeId;
        ELSE
            tmp_loadedIDState := 0;
        END_IF;
    ELSE
        tmp_validState := FALSE;
        tmp_loadedIDState := 0;
    END_IF;
END_IF;

valid := tmp_validState;
loadedID := tmp_loadedIDState;
tmp_prevLoadCmd := loadCmd;

END_FUNCTION_BLOCK