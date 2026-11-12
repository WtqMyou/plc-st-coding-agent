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
    idx       : INT;
    found     : BOOL;
    emptySlot : INT;
END_VAR

// Reset outputs at start of each scan cycle
error             := FALSE;
status            := 16#0000;
recipeAdded       := FALSE;
recipeDeleted     := FALSE;
recipeModified    := FALSE;
recipeQueryResult.recipeID             := 0;
recipeQueryResult.ingredientType       := 0;
recipeQueryResult.ingredientRatio      := 0.0;
recipeQueryResult.productionTemperature:= 0.0;

// Initialize local state
found     := FALSE;
emptySlot := 0;

// PUB009: Query recipe by recipeID
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
    // Check for duplicate recipeID
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
        // Find first empty slot (smallest index)
        emptySlot := 0;
        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = 0 THEN
                emptySlot := idx;
                EXIT;
            END_IF;
        END_FOR;
        
        IF emptySlot = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[emptySlot].recipeID              := recipeIn.recipeID;
            recipe[emptySlot].ingredientType        := recipeIn.ingredientType;
            recipe[emptySlot].ingredientRatio       := recipeIn.ingredientRatio;
            recipe[emptySlot].productionTemperature := recipeIn.productionTemperature;
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
            recipeDeleted := TRUE;
            found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    
    IF NOT found THEN
        error := TRUE;
        status := 16#8004;
    END_IF;
END_IF;

// PUB012: Modify existing recipe
IF modifyRecipe THEN
    found := FALSE;
    FOR idx := 1 TO 10 DO
        IF recipe[idx].recipeID = recipeIn.recipeID THEN
            recipe[idx].recipeID              := recipeIn.recipeID;
            recipe[idx].ingredientType        := recipeIn.ingredientType;
            recipe[idx].ingredientRatio       := recipeIn.ingredientRatio;
            recipe[idx].productionTemperature := recipeIn.productionTemperature;
            recipeModified := TRUE;
            found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    
    IF NOT found THEN
        error := TRUE;
        status := 16#8005;
    END_IF;
END_IF;
END_FUNCTION_BLOCK