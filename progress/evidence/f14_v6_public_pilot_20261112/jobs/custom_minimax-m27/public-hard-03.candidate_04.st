Looking at the bounded status violations (S7, S9, S10 at position 2), the issue is that unconditional reset of `error` and `status` at the start of each call causes values to be cleared even when no operation is active. The bounded checker expects these values to persist between calls when no new operation is triggered, and to transition correctly through operation sequences.

The fix: Only reset `error` and `status` inside each active operation block, preserving state when no command input is asserted.

TYPE ST_Recipe :
STRUCT
    recipeID               : INT;
    ingredientType         : INT;
    ingredientRatio        : REAL;
    productionTemperature  : REAL;
END_STRUCT
END_TYPE

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
    tmp_index      : INT;
    tmp_found      : BOOL;
    tmp_emptySlot  : INT;
    tmp_emptyFound : BOOL;
END_VAR

    recipeAdded  := FALSE;
    recipeDeleted  := FALSE;
    recipeModified := FALSE;

    IF addRecipe THEN
        error  := FALSE;
        status := 16#0000;

        tmp_found      := FALSE;
        tmp_emptySlot  := 0;
        tmp_emptyFound := FALSE;

        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                EXIT;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            FOR tmp_index := 1 TO 10 DO
                IF recipe[tmp_index].recipeID = 0 THEN
                    tmp_emptySlot  := tmp_index;
                    tmp_emptyFound := TRUE;
                    EXIT;
                END_IF;
            END_FOR;
        END_IF;

        IF tmp_found THEN
            error  := TRUE;
            status := 16#8002;
        ELSIF NOT tmp_emptyFound THEN
            error  := TRUE;
            status := 16#8003;
        ELSE
            recipe[tmp_emptySlot] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
        RETURN;
    END_IF;

    IF deleteRecipe THEN
        error  := FALSE;
        status := 16#0000;

        tmp_found := FALSE;

        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                EXIT;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            error  := TRUE;
            status := 16#8004;
        ELSE
            recipe[tmp_index].recipeID := 0;
            recipeDeleted := TRUE;
        END_IF;
        RETURN;
    END_IF;

    IF modifyRecipe THEN
        error  := FALSE;
        status := 16#0000;

        tmp_found := FALSE;

        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                EXIT;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            error  := TRUE;
            status := 16#8005;
        ELSE
            recipe[tmp_index] := recipeIn;
            recipeModified := TRUE;
        END_IF;
        RETURN;
    END_IF;

    IF queryRecipe THEN
        error  := FALSE;
        status := 16#0000;

        tmp_found := FALSE;

        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                recipeQueryResult := recipe[tmp_index];
                EXIT;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            error  := TRUE;
            status := 16#8001;
        END_IF;
        RETURN;
    END_IF;

END_FUNCTION_BLOCK