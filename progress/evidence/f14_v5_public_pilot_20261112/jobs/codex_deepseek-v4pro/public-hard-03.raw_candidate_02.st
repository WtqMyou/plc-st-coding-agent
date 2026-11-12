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
- Request inputs are level-triggered; no edge or latch storage is added.
- recipeAdded/recipeDeleted/recipeModified are true only on a successful scan of the matching request, otherwise false.
- error/status clear at scan start; any failed request in the scan sets them.
- Query success overwrites recipeQueryResult; a failed query leaves it unchanged.
- Add checks duplicate first, then finds the smallest empty index, then checks full database.
- Delete clears only recipeID in the matched slot.
- Modify replaces the entire matched ST_Recipe with recipeIn.
- Empty slots are identified by recipeID = 0 and are ignored during normal searches.
- Simultaneous requests are unspecified; they are evaluated in interface order add/delete/modify/query.
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
        END_IF;
    END_IF;
END_IF;

IF deleteRecipe THEN
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
    END_IF;
END_IF;

IF modifyRecipe THEN
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
    END_IF;
END_IF;

IF queryRecipe THEN
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
    END_IF;
END_IF;

END_FUNCTION_BLOCK