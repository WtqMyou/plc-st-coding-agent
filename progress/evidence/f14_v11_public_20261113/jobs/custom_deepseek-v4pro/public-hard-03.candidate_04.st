TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK RecipeManagement
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
    trg_add : R_TRIG;
    trg_delete : R_TRIG;
    trg_modify : R_TRIG;
    trg_query : R_TRIG;
    tmp_i : INT;
    tmp_idx : INT;
    tmp_empty : INT;
    tmp_duplicate : BOOL;
    tmp_count : INT;
END_VAR

(* ENGINEERING_CONTRACT
   Pub outputs recipeAdded/Deleted/Modified are one-scan success pulses; no latch.
   error/status are combinational: FALSE/0 on success or idle, TRUE/code on specified failure.
   recipe array persists in IN_OUT slots. Add uses first empty slot; delete clears ID only; modify replaces whole recipe.
   Query/delete/modify search only non-zero recipeID; add duplicate check includes recipeID 0 as empty-slot duplicate.
   Multiple simultaneous request inputs are unspecified; implementation reports error=TRUE, status=16#8000 and performs none.
   Boundary: recipeID 0 is never a queryable/deletable/modifiable identifier.
   recipeQueryResult is retained after a successful query until the next successful query. It is not cleared on idle or on an unsuccessful query.
*)
(* CONTRACT_RULES [] *)

trg_add(CLK := addRecipe);
trg_delete(CLK := deleteRecipe);
trg_modify(CLK := modifyRecipe);
trg_query(CLK := queryRecipe);

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 0;

tmp_count := 0;
IF trg_add.Q THEN
    tmp_count := tmp_count + 1;
END_IF;
IF trg_delete.Q THEN
    tmp_count := tmp_count + 1;
END_IF;
IF trg_modify.Q THEN
    tmp_count := tmp_count + 1;
END_IF;
IF trg_query.Q THEN
    tmp_count := tmp_count + 1;
END_IF;

IF tmp_count > 1 THEN
    error := TRUE;
    status := 16#8000;
    RETURN;
END_IF;

IF trg_add.Q THEN
    tmp_duplicate := FALSE;
    FOR tmp_i := 1 TO 10 DO
        IF recipe[tmp_i].recipeID = recipeIn.recipeID THEN
            tmp_duplicate := TRUE;
            EXIT;
        END_IF;
    END_FOR;

    IF tmp_duplicate THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        tmp_empty := 0;
        FOR tmp_i := 1 TO 10 DO
            IF recipe[tmp_i].recipeID = 0 THEN
                tmp_empty := tmp_i;
                EXIT;
            END_IF;
        END_FOR;

        IF tmp_empty = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[tmp_empty] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;

ELSIF trg_delete.Q THEN
    tmp_idx := 0;
    IF recipeIn.recipeID <> 0 THEN
        FOR tmp_i := 1 TO 10 DO
            IF recipe[tmp_i].recipeID = recipeIn.recipeID THEN
                tmp_idx := tmp_i;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_idx = 0 THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[tmp_idx].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;

ELSIF trg_modify.Q THEN
    tmp_idx := 0;
    IF recipeIn.recipeID <> 0 THEN
        FOR tmp_i := 1 TO 10 DO
            IF recipe[tmp_i].recipeID = recipeIn.recipeID THEN
                tmp_idx := tmp_i;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_idx = 0 THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[tmp_idx] := recipeIn;
        recipeModified := TRUE;
    END_IF;

ELSIF trg_query.Q THEN
    tmp_idx := 0;
    IF recipeIn.recipeID <> 0 THEN
        FOR tmp_i := 1 TO 10 DO
            IF recipe[tmp_i].recipeID = recipeIn.recipeID THEN
                tmp_idx := tmp_i;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_idx = 0 THEN
        error := TRUE;
        status := 16#8001;
    ELSE
        recipeQueryResult := recipe[tmp_idx];
    END_IF;
END_IF;

END_FUNCTION_BLOCK