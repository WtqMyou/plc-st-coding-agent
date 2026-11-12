TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_RecipeManager
VAR_INPUT
    addRecipe : BOOL;
    deleteRecipe : BOOL;
    modifyRecipe : BOOL;
    queryRecipe : BOOL;
    recipeIn : ST_Recipe;
END_VAR
VAR_OUTPUT
    recipeAdded : BOOL;
    recipeDeleted : BOOL;
    recipeModified : BOOL;
    recipeQueryResult : ST_Recipe;
    error : BOOL;
    status : WORD;
END_VAR
VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR
VAR
    local_i : INT;
    local_matchIndex : INT;
    local_emptyIndex : INT;
    local_found : BOOL;
    local_emptyFound : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
  Outputs/database behavior:
  - recipeAdded/recipeDeleted/recipeModified: pulse TRUE only on a successful same-scan command, cleared at scan start.
  - recipeQueryResult: cleared at scan start; rewritten only on a successful query.
  - error/status: set on command failure per PUB009-PUB012, otherwise no error.
  - Add checks duplicate before full, then stores at smallest empty index (PUB010).
  - Delete clears only the matching recipeID (PUB011); modify replaces the matching slot (PUB012).
  - Query ID not found => error=TRUE, status=16#8001 (PUB009).
  - Add duplicate => 16#8002; add full => 16#8003 (PUB010).
  - Delete ID not found => 16#8004 (PUB011); modify ID not found => 16#8005 (PUB012).
  - recipeID 0 denotes an empty slot (PUB008).
  - Simultaneous commands are unspecified by task text; implemented with interface-order priority:
    addRecipe > deleteRecipe > modifyRecipe > queryRecipe. The higher-priority command is executed,
    lower-priority commands are not processed in that scan.
  - Bounds: ARRAY[1..10], INT and REAL data preserved exactly (PUB008).
*)

(* CONTRACT_RULES [] *)

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
recipeQueryResult.recipeID := 0;
recipeQueryResult.ingredientType := 0;
recipeQueryResult.ingredientRatio := 0.0;
recipeQueryResult.productionTemperature := 0.0;
error := FALSE;
status := 16#0000;

IF addRecipe THEN
    local_found := FALSE;
    local_emptyFound := FALSE;
    local_emptyIndex := 0;

    FOR local_i := 1 TO 10 BY 1 DO
        IF recipe[local_i].recipeID = recipeIn.recipeID THEN
            local_found := TRUE;
        END_IF;

        IF (NOT local_emptyFound) AND (recipe[local_i].recipeID = 0) THEN
            local_emptyIndex := local_i;
            local_emptyFound := TRUE;
        END_IF;
    END_FOR;

    IF local_found THEN
        error := TRUE;
        status := 16#8002;
    ELSIF NOT local_emptyFound THEN
        error := TRUE;
        status := 16#8003;
    ELSE
        recipe[local_emptyIndex] := recipeIn;
        recipeAdded := TRUE;
        error := FALSE;
        status := 16#0000;
    END_IF;

ELSIF deleteRecipe THEN
    local_found := FALSE;
    local_matchIndex := 0;

    IF recipeIn.recipeID <> 0 THEN
        FOR local_i := 1 TO 10 BY 1 DO
            IF (NOT local_found) AND (recipe[local_i].recipeID = recipeIn.recipeID) THEN
                local_matchIndex := local_i;
                local_found := TRUE;
            END_IF;
        END_FOR;
    END_IF;

    IF local_found THEN
        recipe[local_matchIndex].recipeID := 0;
        recipeDeleted := TRUE;
        error := FALSE;
        status := 16#0000;
    ELSE
        error := TRUE;
        status := 16#8004;
    END_IF;

ELSIF modifyRecipe THEN
    local_found := FALSE;
    local_matchIndex := 0;

    IF recipeIn.recipeID <> 0 THEN
        FOR local_i := 1 TO 10 BY 1 DO
            IF (NOT local_found) AND (recipe[local_i].recipeID = recipeIn.recipeID) THEN
                local_matchIndex := local_i;
                local_found := TRUE;
            END_IF;
        END_FOR;
    END_IF;

    IF local_found THEN
        recipe[local_matchIndex] := recipeIn;
        recipeModified := TRUE;
        error := FALSE;
        status := 16#0000;
    ELSE
        error := TRUE;
        status := 16#8005;
    END_IF;

ELSIF queryRecipe THEN
    local_found := FALSE;
    local_matchIndex := 0;

    IF recipeIn.recipeID <> 0 THEN
        FOR local_i := 1 TO 10 BY 1 DO
            IF (NOT local_found) AND (recipe[local_i].recipeID = recipeIn.recipeID) THEN
                local_matchIndex := local_i;
                local_found := TRUE;
            END_IF;
        END_FOR;
    END_IF;

    IF local_found THEN
        recipeQueryResult := recipe[local_matchIndex];
        error := FALSE;
        status := 16#0000;
    ELSE
        error := TRUE;
        status := 16#8001;
    END_IF;
END_IF;
END_FUNCTION_BLOCK