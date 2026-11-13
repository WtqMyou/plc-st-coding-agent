(*
ENGINEERING_CONTRACT
================================================================================
PUB001  | Activation      : loadTrig.Q & NOT running & valid slot bounds
PUB002  | Deactivation    : loadTrig.Q & NOT running & invalid bounds/slot/content
PUB003  | Retention       : running OR NOT loadTrig.Q → valid,loadedID held
PUB004  | Same-scan order : edge detection → bounds check → slot access → latch
PUB006  | Boundary        : selSlot < 1 | selSlot > 8 → valid=FALSE, loadedID=0
PUB007  | Ratio bounds    : totalRatio < 99.0 | > 101.0 → invalid
PUB008  | Temp bounds     : temperature < 30.0 | > 180.0 → invalid
PUB009  | Content check   : recipeID = 0 → slot empty → invalid
PUB010  | Units           : REAL literals for bounds (inclusive)
PUB013  | Rising edge     : R_TRIG detects loadCmd 0→1 transition
N10-S4  | Production hold : running → loadedID = prev(loadedID)
N10-S9  | No-edge hold    : NOT loadTrig.Q → loadedID = prev(loadedID)
================================================================================
*)
(* CONTRACT_RULES [] *)

TYPE ST_Recipe :
STRUCT
    recipeID    : INT;
    totalRatio  : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    recipe    : ARRAY[1..8] OF ST_Recipe;
    selSlot   : INT;
    loadCmd   : BOOL;
    running   : BOOL;
END_VAR

VAR_OUTPUT
    valid     : BOOL;
    loadedID  : INT;
END_VAR

VAR
    loadTrig  : R_TRIG;
END_VAR

loadTrig(CLK := loadCmd);

IF loadTrig.Q AND NOT running THEN
    IF selSlot >= 1 AND selSlot <= 8 THEN
        valid := (recipe[selSlot].recipeID <> 0)
              AND (recipe[selSlot].totalRatio >= 99.0)
              AND (recipe[selSlot].totalRatio <= 101.0)
              AND (recipe[selSlot].temperature >= 30.0)
              AND (recipe[selSlot].temperature <= 180.0);

        IF valid THEN
            loadedID := recipe[selSlot].recipeID;
        ELSE
            loadedID := 0;
        END_IF;
    ELSE
        valid    := FALSE;
        loadedID := 0;
    END_IF;
ELSE
    IF NOT loadTrig.Q AND NOT running THEN
        ; // Retain valid, loadedID
    END_IF;
END_IF;

IF running THEN
    ; // Retain valid, loadedID
END_IF;

END_FUNCTION_BLOCK