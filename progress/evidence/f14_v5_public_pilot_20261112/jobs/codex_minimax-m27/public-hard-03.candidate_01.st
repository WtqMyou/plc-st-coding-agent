(* ENGINEERING_CONTRACT: Recipe Management System FB_RecipeManager
+------------------------------------------------------------------
| PUB001-006: CRUD operations on recipe database (ARRAY[1..10])
| Output State Groups:
|   - recipeAdded/Deleted/Modified: activation on success, reset
|     when input goes FALSE (level-triggered, same-scan)
|   - recipeQueryResult: populated on success (no separate success flag)
|   - error+status: activation on failure, reset on success
| Priority: Sequential IF chain; query > add > delete > modify
| Units: recipeID(INT), ingredientType(INT), ingredientRatio(REAL),
|        productionTemperature(REAL)
| Boundaries: recipeID=0 denotes empty slot; array bounds 1..10
+------------------------------------------------------------------ *)

TYPE ST_Recipe : STRUCT
    recipeID             : INT;
    ingredientType       : INT;
    ingredientRatio      : REAL;
    productionTemperature: REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_RecipeManager
VAR_INPUT
    addRecipe    : BOOL;
    deleteRecipe : BOOL;
    modifyRecipe : BOOL;
    queryRecipe  : BOOL;
    recipeIn     : ST_Recipe;
END_VAR
VAR_OUTPUT
    recipeAdded       : BOOL := FALSE;
    recipeDeleted     : BOOL := FALSE;
    recipeModified    : BOOL := FALSE;
    recipeQueryResult : ST_Recipe;
    error             : BOOL := FALSE;
    status            : WORD := 16#0000;
END_VAR
VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR
VAR
    idx     : INT;
    found   : BOOL;
    emptyIdx: INT;
END_VAR

// Initialize per scan
error             := FALSE;
status            := 16#0000;
recipeAdded       := FALSE;
recipeDeleted     := FALSE;
recipeModified    := FALSE;
recipeQueryResult.recipeID             := 0;
recipeQueryResult.ingredientType       := 0;
recipeQueryResult.ingredientRatio      := 0.0;
recipeQueryResult.productionTemperature:= 0.0;

// PUB009: Query by recipeID
IF queryRecipe THEN
    found := FALSE;
    FOR idx := 1 TO 10 DO
        IF recipe[idx].recipeID = recipeIn.recipeID THEN
            recipeQueryResult := recipe[idx];
            found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    IF NOT found THEN
        error := TRUE;
        status := 16#8001;
    END_IF;
END_IF;

// PUB010: Add new recipe
IF addRecipe THEN
    found := FALSE;
    FOR idx := 1 TO 10 DO
        IF recipe[idx].recipeID = recipeIn.recipeID THEN
            found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    IF found THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        emptyIdx := 0;
        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = 0 THEN
                emptyIdx := idx;
                EXIT;
            END_IF;
        END_FOR;
        IF emptyIdx = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[emptyIdx] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;
END_IF;

// PUB011: Delete recipe by setting recipeID to 0
IF deleteRecipe THEN
    found := FALSE;
    FOR idx := 1 TO 10 DO
        IF recipe[idx].recipeID = recipeIn.recipeID THEN
            recipe[idx].recipeID := 0;
            found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    IF NOT found THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipeDeleted := TRUE;
    END_IF;
END_IF;

// PUB012: Modify existing recipe
IF modifyRecipe THEN
    found := FALSE;
    FOR idx := 1 TO 10 DO
        IF recipe[idx].recipeID = recipeIn.recipeID THEN
            recipe[idx] := recipeIn;
            found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    IF NOT found THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipeModified := TRUE;
    END_IF;
END_IF;
END_FUNCTION_BLOCK