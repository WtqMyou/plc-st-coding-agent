TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    totalRatio : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE;

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
    tmp_prev_load_cmd : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
valid: activates only on an accepted rising loadCmd edge while not running and all checks pass.
valid: holds in every non-accepting scan, including all running scans and held loadCmd.
valid: deactivates on an accepted rising edge when the slot is empty, out of range, or any numeric check fails.
loadedID: updates only on an accepted rising edge; otherwise retains its previous value, including while running.
loadedID: set to recipe[selSlot].recipeID on successful load, or 0 on any accepted invalid load.
Same-scan priority: running suppresses the load-edge action before any slot validation happens.
Boundaries: slots are INT in [1,8]; totalRatio is REAL in [99.0,101.0]; temperature is REAL in [30.0,180.0].
Edge memory: tmp_prev_load_cmd is updated at the end of every scan; no extra reset or interlock is invented.
Initial outputs are unspecified and are left at their default zero values.
*)

(* CONTRACT_RULES [] *)

IF loadCmd AND NOT tmp_prev_load_cmd THEN
    IF NOT running THEN
        IF (selSlot < 1) OR (selSlot > 8) THEN
            valid := FALSE;
            loadedID := 0;
        ELSIF recipe[selSlot].recipeID = 0 THEN
            valid := FALSE;
            loadedID := 0;
        ELSIF (recipe[selSlot].totalRatio < 99.0)
           OR (recipe[selSlot].totalRatio > 101.0) THEN
            valid := FALSE;
            loadedID := 0;
        ELSIF (recipe[selSlot].temperature < 30.0)
           OR (recipe[selSlot].temperature > 180.0) THEN
            valid := FALSE;
            loadedID := 0;
        ELSE
            valid := TRUE;
            loadedID := recipe[selSlot].recipeID;
        END_IF;
    END_IF;
END_IF;

tmp_prev_load_cmd := loadCmd;

END_FUNCTION_BLOCK