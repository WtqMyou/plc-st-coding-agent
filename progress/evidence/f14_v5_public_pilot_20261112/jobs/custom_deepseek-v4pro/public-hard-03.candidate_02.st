TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

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
    trigAdd : R_TRIG;
    trigDelete : R_TRIG;
    trigModify : R_TRIG;
    trigQuery : R_TRIG;
    addPulse : BOOL;
    deletePulse : BOOL;
    modifyPulse : BOOL;
    queryPulse : BOOL;
    i : INT;
    foundIndex : INT;
    emptyIndex : INT;
    duplicate : BOOL;
END_VAR

(*
ENGINEERING_CONTRACT
- Commands are edge-triggered: only the rising edge of each request executes the operation once.
- Priority when simultaneous edges occur: add > delete > modify > query (IF/ELSIF chain). Unspecified by task.
- Default outputs: success flags FALSE, error FALSE, status 0, recipeQueryResult zeroed each scan.
- error/status remain FALSE/0 on success; set to 16#8001..16#8005 on respective failure.
- recipe array is persistent inout storage. Add fills the lowest recipeID=0 slot; delete sets recipeID=0 only; modify overwrites the matched slot with the full input recipe.
- recipeID=0 is reserved as empty; query/delete/modify treat 0 as “not found”; add rejects 0 with duplicate error 16#8002 (as it conflicts with empty slots).
- PUB009-PUB012 define error codes and operations.
*)

(* Rising-edge detection for all command inputs *)
trigAdd(CLK := addRecipe);
addPulse := trigAdd.Q;
trigDelete(CLK := deleteRecipe);
deletePulse := trigDelete.Q;
trigModify(CLK := modifyRecipe);
modifyPulse := trigModify.Q;
trigQuery(CLK := queryRecipe);
queryPulse := trigQuery.Q;

(* Default outputs each scan *)
recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := WORD#16#0000;
recipeQueryResult.recipeID := 0;
recipeQueryResult.ingredientType := 0;
recipeQueryResult.ingredientRatio := 0.0;
recipeQueryResult.productionTemperature := 0.0;

(* Add recipe *)
IF addPulse THEN
    duplicate := FALSE;
    emptyIndex := 0;

    (* recipeID=0 is reserved as empty slot; reject as duplicate *)
    IF recipeIn.recipeID = 0 THEN
        duplicate := TRUE;
    ELSE
        FOR i := 1 TO 10 DO
            IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
                duplicate := TRUE;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF duplicate THEN
        error := TRUE;
        status := WORD#16#8002;
    ELSE
        (* Find smallest empty slot *)
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = 0 THEN
                emptyIndex := i;
                EXIT;
            END_IF;
        END_FOR;

        IF emptyIndex = 0 THEN
            error := TRUE;
            status := WORD#16#8003;
        ELSE
            recipe[emptyIndex] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;

(* Delete recipe *)
ELSIF deletePulse THEN
    foundIndex := 0;

    IF recipeIn.recipeID <> 0 THEN
        FOR i := 1 TO 10 DO
            IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
                foundIndex := i;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF foundIndex = 0 THEN
        error := TRUE;
        status := WORD#16#8004;
    ELSE
        recipe[foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;

(* Modify recipe *)
ELSIF modifyPulse THEN
    foundIndex := 0;

    IF recipeIn.recipeID <> 0 THEN
        FOR i := 1 TO 10 DO
            IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
                foundIndex := i;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF foundIndex = 0 THEN
        error := TRUE;
        status := WORD#16#8005;
    ELSE
        recipe[foundIndex] := recipeIn;
        recipeModified := TRUE;
    END_IF;

(* Query recipe *)
ELSIF queryPulse THEN
    foundIndex := 0;

    IF recipeIn.recipeID <> 0 THEN
        FOR i := 1 TO 10 DO
            IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
                foundIndex := i;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF foundIndex = 0 THEN
        error := TRUE;
        status := WORD#16#8001;
    ELSE
        recipeQueryResult := recipe[foundIndex];
    END_IF;
END_IF;

END_FUNCTION_BLOCK