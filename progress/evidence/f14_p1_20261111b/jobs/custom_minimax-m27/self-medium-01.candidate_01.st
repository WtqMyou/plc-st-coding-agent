TYPE ST_Recipe :
STRUCT
    recipeID   : INT;
    totalRatio : REAL;
    temperature: REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    recipe   : ARRAY[1..8] OF ST_Recipe;
    selSlot  : INT;
    loadCmd  : BOOL;
    running  : BOOL;
END_VAR
VAR_OUTPUT
    valid    : BOOL;
    loadedID : INT;
END_VAR
VAR
    prevLoadCmd  : BOOL := FALSE;
    prevRunning  : BOOL := FALSE;
    prevLoadedID : INT  := 0;
    prevValid    : BOOL := FALSE;
END_VAR
VAR_TEMP
    risingLoadCmd : BOOL;
    tmpRecipe     : ST_Recipe;
END_VAR

    // 检测 loadCmd 上升沿
    risingLoadCmd := loadCmd AND NOT prevLoadCmd;

    // 装载逻辑
    IF NOT running AND risingLoadCmd THEN
        // 槽位越界检查：必须先检查，不得访问数组外内存
        IF selSlot < 1 OR selSlot > 8 THEN
            valid   := FALSE;
            loadedID := 0;
        ELSE
            tmpRecipe := recipe[selSlot];
            // 槽位为空检查
            IF tmpRecipe.recipeID = 0 THEN
                valid   := FALSE;
                loadedID := 0;
            // 总配比越界检查 (99.0 <= totalRatio <= 101.0)
            ELSIF tmpRecipe.totalRatio < 99.0 OR tmpRecipe.totalRatio > 101.0 THEN
                valid   := FALSE;
                loadedID := 0;
            // 温度越界检查 (30.0 <= temperature <= 180.0)
            ELSIF tmpRecipe.temperature < 30.0 OR tmpRecipe.temperature > 180.0 THEN
                valid   := FALSE;
                loadedID := 0;
            ELSE
                valid    := TRUE;
                loadedID := tmpRecipe.recipeID;
            END_IF
        END_IF
    ELSE
        // 非装载周期：保持上一拍的值 (包括 running 状态)
        valid    := prevValid;
        loadedID := prevLoadedID;
    END_IF

    // 更新历史状态
    prevLoadCmd  := loadCmd;
    prevRunning  := running;
    prevLoadedID := loadedID;
    prevValid    := valid;

END_FUNCTION_BLOCK