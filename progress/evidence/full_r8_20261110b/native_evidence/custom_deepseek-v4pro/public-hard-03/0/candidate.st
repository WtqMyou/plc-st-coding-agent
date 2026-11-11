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
    prevAdd : BOOL := FALSE;
    prevDelete : BOOL := FALSE;
    prevModify : BOOL := FALSE;
    prevQuery : BOOL := FALSE;
    riseAdd : BOOL;
    riseDelete : BOOL;
    riseModify : BOOL;
    riseQuery : BOOL;
    i : INT;
    found : BOOL;
    emptyIndex : INT;
END_VAR

// 上升沿检测
riseAdd := addRecipe AND NOT prevAdd;
riseDelete := deleteRecipe AND NOT prevDelete;
riseModify := modifyRecipe AND NOT prevModify;
riseQuery := queryRecipe AND NOT prevQuery;

// 默认输出（无请求沿时保持）
recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 0;

// 优先级：查询 > 添加 > 删除 > 修改
IF riseQuery THEN
    // 查询请求
    found := FALSE;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
            recipeQueryResult := recipe[i];
            found := TRUE;
            EXIT;
        END_IF
    END_FOR
    IF NOT found THEN
        error := TRUE;
        status := 16#8001;
        // 清空查询结果
        recipeQueryResult.recipeID := 0;
        recipeQueryResult.ingredientType := 0;
        recipeQueryResult.ingredientRatio := 0.0;
        recipeQueryResult.productionTemperature := 0.0;
    END_IF
ELSIF riseAdd THEN
    // 添加请求
    found := FALSE;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
            found := TRUE;
            EXIT;
        END_IF
    END_FOR
    IF found THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        emptyIndex := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = 0 THEN
                emptyIndex := i;
                EXIT;
            END_IF
        END_FOR
        IF emptyIndex = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[emptyIndex] := recipeIn;
            recipeAdded := TRUE;
        END_IF
    END_IF
ELSIF riseDelete THEN
    // 删除请求
    found := FALSE;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
            // 删除该槽，全部字段归零
            recipe[i].recipeID := 0;
            recipe[i].ingredientType := 0;
            recipe[i].ingredientRatio := 0.0;
            recipe[i].productionTemperature := 0.0;
            found := TRUE;
            EXIT;
        END_IF
    END_FOR
    IF found THEN
        recipeDeleted := TRUE;
    ELSE
        error := TRUE;
        status := 16#8004;
    END_IF
ELSIF riseModify THEN
    // 修改请求
    found := FALSE;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
            recipe[i] := recipeIn;
            found := TRUE;
            EXIT;
        END_IF
    END_FOR
    IF found THEN
        recipeModified := TRUE;
    ELSE
        error := TRUE;
        status := 16#8005;
    END_IF
END_IF

// 更新上一周期信号
prevAdd := addRecipe;
prevDelete := deleteRecipe;
prevModify := modifyRecipe;
prevQuery := queryRecipe;

END_FUNCTION_BLOCK