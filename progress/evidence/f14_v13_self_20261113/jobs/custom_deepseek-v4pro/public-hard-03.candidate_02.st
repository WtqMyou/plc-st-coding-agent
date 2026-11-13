(*
ENGINEERING_CONTRACT
- recipeAdded/Deleted/Modified: rising-edge pulse outputs, TRUE only on the scan where the corresponding request succeeds; no retention; reset next scan (PUB003/004/005).
- error: rising-edge pulse, TRUE only on the scan where an operation fails; no retention; reset next scan (PUB002-005).
- status: WORD code, 0 by default, nonzero only during a failed operation scan (PUB002-005).
- recipeQueryResult: zero-cleared at the start of every scan; holds the full recipe only during a successful query scan (PUB002).
- recipe database: persistent through IN_OUT; add uses smallest empty slot, duplicate check; delete sets recipeID to 0; modify replaces the whole struct (PUB003/004/005).
- Simultaneous requests are processed in the order query, add, delete, modify; unspecified by PUB002-005.
- recipeID 0 is treated as nonexistent for query/delete/modify and as duplicate for add because 0 marks an empty slot (PUB001).
*)
(* CONTRACT_RULES [] *)
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
    tmp_TrigAdd : R_TRIG;
    tmp_TrigDelete : R_TRIG;
    tmp_TrigModify : R_TRIG;
    tmp_TrigQuery : R_TRIG;
    tmp_idx : INT;
    tmp_found : BOOL;
    tmp_foundIdx : INT;
    tmp_emptyIdx : INT;
END_VAR

// Evaluate rising edges once per scan.
tmp_TrigAdd(CLK := addRecipe);
tmp_TrigDelete(CLK := deleteRecipe);
tmp_TrigModify(CLK := modifyRecipe);
tmp_TrigQuery(CLK := queryRecipe);

// Default outputs for this scan.
recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 0;

// Clear query result each scan; successful query will overwrite later.
recipeQueryResult.recipeID := 0;
recipeQueryResult.ingredientType := 0;
recipeQueryResult.ingredientRatio := 0.0;
recipeQueryResult.productionTemperature := 0.0;

// Query operation (PUB002)
IF tmp_TrigQuery.Q THEN
    tmp_foundIdx := 0;
    IF recipeIn.recipeID <> 0 THEN
        FOR tmp_idx := 1 TO 10 DO
            IF recipe[tmp_idx].recipeID = recipeIn.recipeID THEN
                tmp_foundIdx := tmp_idx;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_foundIdx = 0 THEN
        error := TRUE;
        status := 16#8001;
    ELSE
        recipeQueryResult := recipe[tmp_foundIdx];
    END_IF;
END_IF;

// Add operation (PUB003)
IF tmp_TrigAdd.Q THEN
    tmp_found := FALSE;
    tmp_emptyIdx := 0;

    FOR tmp_idx := 1 TO 10 DO
        IF recipe[tmp_idx].recipeID = recipeIn.recipeID THEN
            tmp_found := TRUE;
            EXIT;
        END_IF;
        IF recipe[tmp_idx].recipeID = 0 AND tmp_emptyIdx = 0 THEN
            tmp_emptyIdx := tmp_idx;
        END_IF;
    END_FOR;

    IF tmp_found THEN
        error := TRUE;
        status := 16#8002;
    ELSIF tmp_emptyIdx = 0 THEN
        error := TRUE;
        status := 16#8003;
    ELSE
        recipe[tmp_emptyIdx] := recipeIn;
        recipeAdded := TRUE;
    END_IF;
END_IF;

// Delete operation (PUB004)
IF tmp_TrigDelete.Q THEN
    tmp_foundIdx := 0;
    IF recipeIn.recipeID <> 0 THEN
        FOR tmp_idx := 1 TO 10 DO
            IF recipe[tmp_idx].recipeID = recipeIn.recipeID THEN
                tmp_foundIdx := tmp_idx;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_foundIdx = 0 THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[tmp_foundIdx].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;
END_IF;

// Modify operation (PUB005)
IF tmp_TrigModify.Q THEN
    tmp_foundIdx := 0;
    IF recipeIn.recipeID <> 0 THEN
        FOR tmp_idx := 1 TO 10 DO
            IF recipe[tmp_idx].recipeID = recipeIn.recipeID THEN
                tmp_foundIdx := tmp_idx;
                EXIT;
            END_IF;
        END_FOR;
    END_IF;

    IF tmp_foundIdx = 0 THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[tmp_foundIdx] := recipeIn;
        recipeModified := TRUE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK