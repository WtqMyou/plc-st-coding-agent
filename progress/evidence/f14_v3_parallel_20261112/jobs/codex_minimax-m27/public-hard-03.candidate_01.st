TYPE ST_Recipe :
STRUCT
    recipeID : INT;              (* Recipe identifier; zero denotes an unused database slot. *)
    ingredientType : INT;        (* Ingredient-type identifier. *)
    ingredientRatio : REAL;      (* Ingredient proportion. *)
    productionTemperature : REAL; (* Production temperature. *)
END_STRUCT;
END_TYPE;

FUNCTION_BLOCK RecipeManager
VAR_INPUT
    addRecipe : BOOL;            (* Add Recipe Request Signal *)
    deleteRecipe : BOOL;         (* Delete Recipe Request Signal *)
    modifyRecipe : BOOL;         (* Modify Recipe Request Signal *)
    queryRecipe : BOOL;          (* Query Recipe Request Signal *)
    recipeIn : ST_Recipe;        (* Input Recipe *)
END_VAR

VAR_OUTPUT
    recipeAdded : BOOL;          (* Recipe Added Success Indicator *)
    recipeDeleted : BOOL;        (* Recipe Deleted Success Indicator *)
    recipeModified : BOOL;       (* Recipe Modified Success Indicator *)
    recipeQueryResult : ST_Recipe; (* Recipe Query Result Output *)
    error : BOOL;                (* Error Status Indicator *)
    status : WORD;               (* Status Code *)
END_VAR

VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe; (* Recipe Database *)
END_VAR

VAR
    prevAddRecipe : BOOL;
    prevDeleteRecipe : BOOL;
    prevModifyRecipe : BOOL;
    prevQueryRecipe : BOOL;
    i : INT;
    foundIndex : INT;
    emptySlotIndex : INT;
END_VAR

(* Initialize on first cycle *)
IF prevAddRecipe = FALSE AND prevDeleteRecipe = FALSE AND 
   prevModifyRecipe = FALSE AND prevQueryRecipe = FALSE THEN
    FOR i := 1 TO 10 DO
        recipe[i].recipeID := 0;
    END_FOR;
END_IF;

(* Clear output flags *)
recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 16#0000;

(* Process operations based on rising edge detection *)
IF queryRecipe AND NOT prevQueryRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;
    
    IF foundIndex > 0 THEN
        recipeQueryResult := recipe[foundIndex];
    ELSE
        error := TRUE;
        status := 16#8001;
    END_IF;

ELSIF addRecipe AND NOT prevAddRecipe THEN
    (* Check for duplicate recipeID *)
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;
    
    IF foundIndex > 0 THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        (* Find first empty slot *)
        emptySlotIndex := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = 0 THEN
                emptySlotIndex := i;
                EXIT;
            END_IF;
        END_FOR;
        
        IF emptySlotIndex = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[emptySlotIndex] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;

ELSIF deleteRecipe AND NOT prevDeleteRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;
    
    IF foundIndex = 0 THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;

ELSIF modifyRecipe AND NOT prevModifyRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;
    
    IF foundIndex = 0 THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[foundIndex] := recipeIn;
        recipeModified := TRUE;
    END_IF;
END_IF;

(* Update edge detection state *)
prevAddRecipe := addRecipe;
prevDeleteRecipe := deleteRecipe;
prevModifyRecipe := modifyRecipe;
prevQueryRecipe := queryRecipe;

END_FUNCTION_BLOCK