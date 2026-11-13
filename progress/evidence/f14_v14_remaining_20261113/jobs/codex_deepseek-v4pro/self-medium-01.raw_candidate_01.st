TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    totalRatio : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE

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
    tmp_cmd_was_high : BOOL := FALSE;
    tmp_rising : BOOL;
    tmp_prev_valid : BOOL;
    tmp_prev_loaded : INT;
END_VAR

(* ENGINEERING_CONTRACT
- valid activates only on !running AND rising(loadCmd); otherwise it holds the prior value.
- valid TRUE iff selSlot is 1..8 and the selected slot is non-empty with totalRatio in [99.0,101.0] and temperature in [30.0,180.0]; otherwise FALSE.
- loadedID is set to the selected recipeID on a valid load and to 0 on an invalid load; otherwise it holds the prior value.
- running TRUE suppresses loading and preserves prior valid and loadedID (N10-S4,S9).
- recipe[selSlot] is dereferenced only after bounds validation; a held loadCmd does not retrigger (S5,S6).
*)

(* CONTRACT_RULES [] *)

tmp_rising := loadCmd AND NOT tmp_cmd_was_high;
tmp_prev_valid := valid;
tmp_prev_loaded := loadedID;

IF (NOT running) AND tmp_rising THEN
    IF (selSlot >= 1) AND (selSlot <= 8) THEN
        IF (recipe[selSlot].recipeID <> 0)
           AND (recipe[selSlot].totalRatio >= 99.0)
           AND (recipe[selSlot].totalRatio <= 101.0)
           AND (recipe[selSlot].temperature >= 30.0)
           AND (recipe[selSlot].temperature <= 180.0) THEN
            valid := TRUE;
            loadedID := recipe[selSlot].recipeID;
        ELSE
            valid := FALSE;
            loadedID := 0;
        END_IF;
    ELSE
        valid := FALSE;
        loadedID := 0;
    END_IF;
ELSE
    valid := tmp_prev_valid;
    loadedID := tmp_prev_loaded;
END_IF;

tmp_cmd_was_high := loadCmd;
END_FUNCTION_BLOCK