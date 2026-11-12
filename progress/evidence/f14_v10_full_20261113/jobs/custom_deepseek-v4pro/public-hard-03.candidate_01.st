TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_RecipeManagement
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
    tmp_i : INT;
    tmp_found : BOOL;
    tmp_index : INT;
    tmp_emptyIndex : INT;
    tmp_cmdCount : INT;
    tmp_emptyRecipe : ST_Recipe;
END_VAR

(*
ENGINEERING_CONTRACT
recipeAdded/Deleted/Modified: pulse TRUE only when exactly one matching request is TRUE and operation succeeds; not latched.
recipeQueryResult: valid only on successful query; otherwise zero struct. Not latched.
error/status: same-scan result; success/no command => error=FALSE,status=0. Error codes PUB003-PUB005, multiple commands => 16#8006.
recipe IN_OUT: caller retains; changed only on successful add/delete/modify. Add uses smallest empty index (PUB003).
Search ignores slots where recipeID=0. Units: raw REAL values; no scaling. Simultaneous commands are unsupported and modify nothing.
*)

(* CONTRACT_RULES [] *)

tmp_emptyRecipe.recipeID := 0;
tmp_emptyRecipe.ingredientType := 0;
tmp_emptyRecipe.ingredientRatio := 0.0;
tmp_emptyRecipe.productionTemperature := 0.0;

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
recipeQueryResult := tmp_emptyRecipe;
error := FALSE;
status := 0;

tmp_cmdCount := 0;
IF addRecipe THEN
    tmp_cmdCount := tmp_cmdCount + 1;
END_IF;
IF deleteRecipe THEN
    tmp_cmdCount := tmp_cmdCount + 1;
END_IF;
IF modifyRecipe THEN
    tmp_cmdCount := tmp_cmdCount + 1;
END_IF;
IF queryRecipe THEN
    tmp_cmdCount := tmp_cmdCount + 1;
END_IF;

IF tmp_cmdCount > 1 THEN
    error := TRUE;
    status := 16#8006;
    RETURN;
END_IF;

IF addRecipe THEN
    tmp_found := FALSE;
    tmp_index := 0;
    FOR tmp_i := 1 TO 10 DO
        IF (recipe[tmp_i].recipeID <> 0) AND (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
            tmp_found := TRUE;
            tmp_index := tmp_i;
            EXIT;
        END_IF;
    END_FOR;

    IF tmp_found THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        tmp_emptyIndex := 0;
        FOR tmp_i := 1 TO 10 DO
            IF recipe[tmp_i].recipeID = 0 THEN
                tmp_emptyIndex := tmp_i;
                EXIT;
            END_IF;
        END_FOR;

        IF tmp_emptyIndex = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[tmp_emptyIndex] := recipeIn;
            recipeAdded := TRUE;
            error := FALSE;
            status := 0;
        END_IF;
    END_IF;
END_IF;

IF deleteRecipe THEN
    tmp_found := FALSE;
    tmp_index := 0;
    FOR tmp_i := 1 TO 10 DO
        IF (recipe[tmp_i].recipeID <> 0) AND (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
            tmp_found := TRUE;
            tmp_index := tmp_i;
            EXIT;
        END_IF;
    END_FOR;

    IF NOT tmp_found THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[tmp_index] := tmp_emptyRecipe;
        recipeDeleted := TRUE;
        error := FALSE;
        status := 0;
    END_IF;
END_IF;

IF modifyRecipe THEN
    tmp_found := FALSE;
    tmp_index := 0;
    FOR tmp_i := 1 TO 10 DO
        IF (recipe[tmp_i].recipeID <> 0) AND (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
            tmp_found := TRUE;
            tmp_index := tmp_i;
            EXIT;
        END_IF;
    END_FOR;

    IF NOT tmp_found THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[tmp_index] := recipeIn;
        recipeModified := TRUE;
        error := FALSE;
        status := 0;
    END_IF;
END_IF;

IF queryRecipe THEN
    tmp_found := FALSE;
    tmp_index := 0;
    FOR tmp_i := 1 TO 10 DO
        IF (recipe[tmp_i].recipeID <> 0) AND (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
            tmp_found := TRUE;
            tmp_index := tmp_i;
            EXIT;
        END_IF;
    END_FOR;

    IF NOT tmp_found THEN
        error := TRUE;
        status := 16#8001;
    ELSE
        recipeQueryResult := recipe[tmp_index];
        error := FALSE;
        status := 0;
    END_IF;
END_IF;

END_FUNCTION_BLOCK