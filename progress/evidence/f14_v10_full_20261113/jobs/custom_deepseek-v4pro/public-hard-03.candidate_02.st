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
    tmp_addReq : BOOL;
    tmp_deleteReq : BOOL;
    tmp_modifyReq : BOOL;
    tmp_queryReq : BOOL;
    prevAdd : BOOL := FALSE;
    prevDelete : BOOL := FALSE;
    prevModify : BOOL := FALSE;
    prevQuery : BOOL := FALSE;
END_VAR

(*
ENGINEERING_CONTRACT
Request signals are edge-triggered (rising edge only).
recipeAdded/Deleted/Modified: one-scan pulse on successful operation; otherwise FALSE.
recipeQueryResult: valid only in the scan of a successful query; zero struct otherwise.
error/status: same-scan result; success/no edge => error=FALSE,status=0.
Simultaneous rising command edges => error=TRUE,status=16#8006; database unchanged.
Database in recipe[] retains state between scans; add uses smallest empty index.
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

tmp_addReq := addRecipe AND NOT prevAdd;
tmp_deleteReq := deleteRecipe AND NOT prevDelete;
tmp_modifyReq := modifyRecipe AND NOT prevModify;
tmp_queryReq := queryRecipe AND NOT prevQuery;

prevAdd := addRecipe;
prevDelete := deleteRecipe;
prevModify := modifyRecipe;
prevQuery := queryRecipe;

tmp_cmdCount := 0;
IF tmp_addReq THEN
    tmp_cmdCount := tmp_cmdCount + 1;
END_IF;
IF tmp_deleteReq THEN
    tmp_cmdCount := tmp_cmdCount + 1;
END_IF;
IF tmp_modifyReq THEN
    tmp_cmdCount := tmp_cmdCount + 1;
END_IF;
IF tmp_queryReq THEN
    tmp_cmdCount := tmp_cmdCount + 1;
END_IF;

IF tmp_cmdCount > 1 THEN
    error := TRUE;
    status := 16#8006;
    RETURN;
END_IF;

IF tmp_addReq THEN
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

IF tmp_deleteReq THEN
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

IF tmp_modifyReq THEN
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

IF tmp_queryReq THEN
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