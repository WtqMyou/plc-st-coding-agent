TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

(* ENGINEERING_CONTRACT
   Outputs: success flags are same-scan level, not latched; they deactivate on the next scan (PUB003-PUB005).
   recipeQueryResult: updated only for a successful query; otherwise zeroed each scan (PUB002).
   error/status: cleared at scan start; a reported operation error retains error and code for that invocation (PUB002-PUB005).
   Add: duplicate check before empty-slot check; uses first empty index; whole struct copy (PUB003).
   Delete: nonzero-ID match; sets only recipeID to 0 (PUB004).
   Modify: nonzero-ID match; whole struct replacement (PUB005).
   Query: nonzero-ID match; whole struct copy to result; missing ID gives 16#8001 (PUB002).
   Array bounds: 1..10; recipeID=0 denotes unused slot and is never returned as a stored recipe.
   Multiple requests: unspecified by the public contract. They are reported as an unsupported combination with
   error=TRUE, status=16#8000, no database update, no success flag, and no query result.
*)
(* CONTRACT_RULES [] *)

FUNCTION_BLOCK RecipeManagementSystem
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
    tmp_foundIndex : INT;
    tmp_emptyIndex : INT;
    tmp_found : BOOL;
    tmp_cmdCount : INT;
END_VAR

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
recipeQueryResult.recipeID := 0;
recipeQueryResult.ingredientType := 0;
recipeQueryResult.ingredientRatio := 0.0;
recipeQueryResult.productionTemperature := 0.0;
error := FALSE;
status := 16#0000;

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
    status := 16#8000;
ELSE
    IF addRecipe THEN
        tmp_found := FALSE;
        tmp_emptyIndex := 0;

        FOR tmp_i := 1 TO 10 DO
            IF recipe[tmp_i].recipeID = recipeIn.recipeID THEN
                tmp_found := TRUE;
            END_IF;

            IF (recipe[tmp_i].recipeID = 0) AND (tmp_emptyIndex = 0) THEN
                tmp_emptyIndex := tmp_i;
            END_IF;
        END_FOR;

        IF tmp_found THEN
            IF NOT error THEN
                error := TRUE;
                status := 16#8002;
            END_IF;
        ELSIF tmp_emptyIndex = 0 THEN
            IF NOT error THEN
                error := TRUE;
                status := 16#8003;
            END_IF;
        ELSE
            recipe[tmp_emptyIndex] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;

    IF deleteRecipe THEN
        tmp_found := FALSE;
        tmp_foundIndex := 0;

        FOR tmp_i := 1 TO 10 DO
            IF (recipe[tmp_i].recipeID <> 0) AND
               (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
                tmp_found := TRUE;
                tmp_foundIndex := tmp_i;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            IF NOT error THEN
                error := TRUE;
                status := 16#8004;
            END_IF;
        ELSE
            recipe[tmp_foundIndex].recipeID := 0;
            recipeDeleted := TRUE;
        END_IF;
    END_IF;

    IF modifyRecipe THEN
        tmp_found := FALSE;
        tmp_foundIndex := 0;

        FOR tmp_i := 1 TO 10 DO
            IF (recipe[tmp_i].recipeID <> 0) AND
               (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
                tmp_found := TRUE;
                tmp_foundIndex := tmp_i;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            IF NOT error THEN
                error := TRUE;
                status := 16#8005;
            END_IF;
        ELSE
            recipe[tmp_foundIndex] := recipeIn;
            recipeModified := TRUE;
        END_IF;
    END_IF;

    IF queryRecipe THEN
        tmp_found := FALSE;
        tmp_foundIndex := 0;

        FOR tmp_i := 1 TO 10 DO
            IF (recipe[tmp_i].recipeID <> 0) AND
               (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
                tmp_found := TRUE;
                tmp_foundIndex := tmp_i;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            IF NOT error THEN
                error := TRUE;
                status := 16#8001;
            END_IF;
        ELSE
            recipeQueryResult := recipe[tmp_foundIndex];
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK