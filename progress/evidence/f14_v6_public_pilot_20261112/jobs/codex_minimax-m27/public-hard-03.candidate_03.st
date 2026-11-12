TYPE ST_Recipe :
STRUCT
    recipeID             : INT;
    ingredientType       : INT;
    ingredientRatio      : REAL;
    productionTemperature: REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_RecipeManagement
VAR_INPUT
    addRecipe    : BOOL;
    deleteRecipe : BOOL;
    modifyRecipe : BOOL;
    queryRecipe  : BOOL;
    recipeIn     : ST_Recipe;
END_VAR

VAR_OUTPUT
    recipeAdded       : BOOL;
    recipeDeleted     : BOOL;
    recipeModified    : BOOL;
    recipeQueryResult : ST_Recipe;
    error             : BOOL;
    status            : WORD;
END_VAR

VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR

VAR
    tmp_idx       : INT;
    tmp_foundIdx  : INT;
    tmp_emptyIdx  : INT;
END_VAR

// ENGINEERING_CONTRACT
(*
PUB001: Recipe management for production line control center
PUB002-006: CRUD operations on recipe database
PUB008: Array[1..10], recipeID=0 denotes empty slot, no duplicate IDs
PUB009: Query - not found => error=TRUE, status=16#8001
PUB010: Add - duplicate => 16#8002, no slot => 16#8003, else store at smallest empty index
PUB011: Delete - not found => 16#8004, else set recipeID=0
PUB012: Modify - not found => 16#8005, else replace entire recipe
Output activation: recipeAdded/recipeDeleted/recipeModified = single-scan TRUE on success
Output retention: error/status persist until next operation; no persistent latch
Same-scan priority: IF/ELSIF chain order = queryRecipe > addRecipe > deleteRecipe > modifyRecipe
Units/boundaries: recipe array[1..10], recipeID=INT (0=empty), ratio/temp=REAL
*)

// CONTRACT_RULES
(* [] *)

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 16#0000;

tmp_foundIdx := 0;
tmp_emptyIdx := 0;

FOR tmp_idx := 1 TO 10 DO
    IF recipe[tmp_idx].recipeID = recipeIn.recipeID THEN
        tmp_foundIdx := tmp_idx;
    END_IF;
    IF recipe[tmp_idx].recipeID = 0 AND tmp_emptyIdx = 0 THEN
        tmp_emptyIdx := tmp_idx;
    END_IF;
END_FOR;

IF queryRecipe THEN
    IF tmp_foundIdx = 0 THEN
        error := TRUE;
        status := 16#8001;
    ELSE
        recipeQueryResult := recipe[tmp_foundIdx];
    END_IF;
ELSIF addRecipe THEN
    IF tmp_foundIdx <> 0 THEN
        error := TRUE;
        status := 16#8002;
    ELSIF tmp_emptyIdx = 0 THEN
        error := TRUE;
        status := 16#8003;
    ELSE
        recipe[tmp_emptyIdx] := recipeIn;
        recipeAdded := TRUE;
    END_IF;
ELSIF deleteRecipe THEN
    IF tmp_foundIdx = 0 THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[tmp_foundIdx].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;
ELSIF modifyRecipe THEN
    IF tmp_foundIdx = 0 THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[tmp_foundIdx] := recipeIn;
        recipeModified := TRUE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK