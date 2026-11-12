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
  - recipeAdded/recipeDeleted/recipeModified: TRUE only on a successful same-scan command, cleared each scan; no hold.
  - recipeQueryResult: written only on a successful query, cleared at scan start; no retention.
  - error/status: set on command failures per PUB009-PUB012, cleared each scan; no hold.
  - Simultaneous commands: addRecipe has priority; then queryRecipe, deleteRecipe, modifyRecipe.
  - Add order: duplicate=16#8002 before full=16#8003; success fills smallest empty index (PUB010).
  - Delete sets only matching recipeID to 0 (PUB011); modify replaces matching slot (PUB012).
  - recipeID 0 is an empty slot marker. Query/delete/modify of ID 0 returns command-specific failure.
  - Bounds: array[1..10], IDs INT, ratios/temperatures REAL (PUB008).
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
END_IF;
END_FUNCTION_BLOCK