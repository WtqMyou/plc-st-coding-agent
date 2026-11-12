TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK RecipeManagementSystem
(*
ENGINEERING_CONTRACT
- Operations are level-triggered; no edge or latch storage is added (PUB002-PUB006).
- recipeAdded/Deleted/Modified are active only during a successful selected scan; otherwise cleared.
- error/status clear each scan unless the selected operation reports a failure.
- Query retains the last successful recipeQueryResult; a missing recipe leaves it unchanged (PUB009).
- Add checks duplicate first, then smallest empty index, otherwise 16#8002/16#8003 (PUB010).
- Delete clears only recipeID in the matched slot (PUB011).
- Modify replaces the whole matched ST_Recipe with recipeIn (PUB012).
- recipeID=0 denotes an empty slot; searches ignore such slots (PUB008).
- Simultaneous requests use priority add > delete > modify > query (unspecified by task).
*)
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
    i : INT;
    foundIndex : INT;
    emptyIndex : INT;
    found : BOOL;
    emptyFound : BOOL;
END_VAR

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 0;

IF addRecipe THEN
    found := FALSE;
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            found := TRUE;
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;

    IF found THEN
        error := TRUE;
        status := WORD#16#8002;
    ELSE
        emptyFound := FALSE;
        emptyIndex := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = 0 THEN
                emptyFound := TRUE;
                emptyIndex := i;
                EXIT;
            END_IF;
        END_FOR;

        IF NOT emptyFound THEN
            error := TRUE;
            status := WORD#16#8003;
        ELSE
            recipe[emptyIndex].recipeID := recipeIn.recipeID;
            recipe[emptyIndex].ingredientType := recipeIn.ingredientType;
            recipe[emptyIndex].ingredientRatio := recipeIn.ingredientRatio;
            recipe[emptyIndex].productionTemperature := recipeIn.productionTemperature;
            recipeAdded := TRUE;
            error := FALSE;
            status := 0;
        END_IF;
    END_IF;

ELSIF deleteRecipe THEN
    found := FALSE;
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            found := TRUE;
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;

    IF NOT found THEN
        error := TRUE;
        status := WORD#16#8004;
    ELSE
        recipe[foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
        error := FALSE;
        status := 0;
    END_IF;

ELSIF modifyRecipe THEN
    found := FALSE;
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            found := TRUE;
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;

    IF NOT found THEN
        error := TRUE;
        status := WORD#16#8005;
    ELSE
        recipe[foundIndex] := recipeIn;
        recipeModified := TRUE;
        error := FALSE;
        status := 0;
    END_IF;

ELSIF queryRecipe THEN
    found := FALSE;
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            found := TRUE;
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;

    IF NOT found THEN
        error := TRUE;
        status := WORD#16#8001;
    ELSE
        recipeQueryResult := recipe[foundIndex];
        error := FALSE;
        status := 0;
    END_IF;
END_IF;

END_FUNCTION_BLOCK