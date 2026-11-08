TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
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
    prevAddRecipe : BOOL := FALSE;
    prevDeleteRecipe : BOOL := FALSE;
    prevModifyRecipe : BOOL := FALSE;
    prevQueryRecipe : BOOL := FALSE;
    addRising : BOOL;
    deleteRising : BOOL;
    modifyRising : BOOL;
    queryRising : BOOL;
    i : INT;
    foundIndex : INT;
    found : BOOL;
    emptyIndex : INT;
    duplicate : BOOL;
END_VAR

// 默认输出复位
recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 0;

// 计算上升沿
addRising := addRecipe AND NOT prevAddRecipe;
deleteRising := deleteRecipe AND NOT prevDeleteRecipe;
modifyRising := modifyRecipe AND NOT prevModifyRecipe;
queryRising := queryRecipe AND NOT prevQueryRecipe;

// 更新历史状态
prevAddRecipe := addRecipe;
prevDeleteRecipe := deleteRecipe;
prevModifyRecipe := modifyRecipe;
prevQueryRecipe := queryRecipe;

// 按优先级处理请求（假设同一时刻只有一个请求被触发）
IF addRising THEN
    // 检查重复
    duplicate := FALSE;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
            duplicate := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    
    IF duplicate THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        // 查找第一个空槽
        emptyIndex := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = 0 THEN
                emptyIndex := i;
                EXIT;
            END_IF;
        END_FOR;
        
        IF emptyIndex = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[emptyIndex] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;
ELSIF deleteRising THEN
    // 查找要删除的配方
    found := FALSE;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
            found := TRUE;
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;
    
    IF NOT found THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;
ELSIF modifyRising THEN
    // 查找要修改的配方
    found := FALSE;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
            found := TRUE;
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;
    
    IF NOT found THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[foundIndex] := recipeIn;
        recipeModified := TRUE;
    END_IF;
ELSIF queryRising THEN
    // 查找要查询的配方
    found := FALSE;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
            found := TRUE;
            recipeQueryResult := recipe[i];
            EXIT;
        END_IF;
    END_FOR;
    
    IF NOT found THEN
        error := TRUE;
        status := 16#8001;
    END_IF;
END_IF;

END_FUNCTION_BLOCK