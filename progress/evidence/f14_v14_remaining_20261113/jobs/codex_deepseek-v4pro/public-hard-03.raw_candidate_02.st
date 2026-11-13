TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_RecipeManagementSystem
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
    tmp_duplicateFound : BOOL;
    tmp_commandCount : INT;
    tmp_blankRecipe : ST_Recipe;
END_VAR

(* ENGINEERING_CONTRACT
   recipeAdded/Deleted/Modified: pulse TRUE only in the scan of a successful sole command; no retention; cleared each scan.
   recipeQueryResult: assigned from the matched recipe on a successful sole query; cleared to blank on all other scans; no retention.
   error/status: combinational per scan; PUB002-PUB006 error codes 16#8001..16#8005 on sole-command failures; 16#0000 on success/no operation.
   database recipe: retained through IN_OUT; altered only by successful add/delete/modify per PUB003-PUB005; slot recipeID=0 means empty.
   same-scan priority: simultaneous command requests are reported as unsupported with 16#8000; PUB011 leaves this case unspecified.
   units/boundaries: identifiers INT, ratios/temperatures REAL copied unchanged; empty slot search returns smallest index in 1..10.
*)
(* CONTRACT_RULES [] *)

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 0;
recipeQueryResult := tmp_blankRecipe;
tmp_commandCount := 0;
tmp_foundIndex := 0;
tmp_emptyIndex := 0;
tmp_duplicateFound := FALSE;

IF addRecipe THEN
    tmp_commandCount := tmp_commandCount + 1;
END_IF;
IF deleteRecipe THEN
    tmp_commandCount := tmp_commandCount + 1;
END_IF;
IF modifyRecipe THEN
    tmp_commandCount := tmp_commandCount + 1;
END_IF;
IF queryRecipe THEN
    tmp_commandCount := tmp_commandCount + 1;
END_IF;

IF tmp_commandCount > 1 THEN
    error := TRUE;
    status := 16#8000;

ELSIF addRecipe THEN
    FOR tmp_i := 1 TO 10 DO
        IF (recipe[tmp_i].recipeID <> 0) AND (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
            tmp_duplicateFound := TRUE;
        END_IF;
    END_FOR;

    IF tmp_duplicateFound THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        FOR tmp_i := 1 TO 10 DO
            IF (recipe[tmp_i].recipeID = 0) AND (tmp_emptyIndex = 0) THEN
                tmp_emptyIndex := tmp_i;
            END_IF;
        END_FOR;

        IF tmp_emptyIndex = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[tmp_emptyIndex] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;

ELSIF deleteRecipe THEN
    FOR tmp_i := 1 TO 10 DO
        IF (recipe[tmp_i].recipeID <> 0) AND (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
            tmp_foundIndex := tmp_i;
        END_IF;
    END_FOR;

    IF tmp_foundIndex = 0 THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[tmp_foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;

ELSIF modifyRecipe THEN
    FOR tmp_i := 1 TO 10 DO
        IF (recipe[tmp_i].recipeID <> 0) AND (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
            tmp_foundIndex := tmp_i;
        END_IF;
    END_FOR;

    IF tmp_foundIndex = 0 THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[tmp_foundIndex] := recipeIn;
        recipeModified := TRUE;
    END_IF;

ELSIF queryRecipe THEN
    FOR tmp_i := 1 TO 10 DO
        IF (recipe[tmp_i].recipeID <> 0) AND (recipe[tmp_i].recipeID = recipeIn.recipeID) THEN
            tmp_foundIndex := tmp_i;
        END_IF;
    END_FOR;

    IF tmp_foundIndex = 0 THEN
        error := TRUE;
        status := 16#8001;
    ELSE
        recipeQueryResult := recipe[tmp_foundIndex];
    END_IF;
END_IF;

END_FUNCTION_BLOCK