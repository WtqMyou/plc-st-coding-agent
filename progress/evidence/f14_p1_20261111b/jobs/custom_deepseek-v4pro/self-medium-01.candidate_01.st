TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    totalRatio : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    recipe : ARRAY[1..8] OF ST_Recipe;
    selSlot : INT;
    loadCmd : BOOL;
    running : BOOL;
END_VAR
VAR_OUTPUT
    valid : BOOL := FALSE;
    loadedID : INT := 0;
END_VAR
VAR
    prev_loadCmd : BOOL := FALSE;
END_VAR

// 仅在未生产且检测到 loadCmd 上升沿时执行装载校验
IF NOT running THEN
    IF loadCmd AND NOT prev_loadCmd THEN
        // 下标越界保护：先判断合法范围，避免访问数组外
        IF selSlot >= 1 AND selSlot <= 8 THEN
            // 校验：槽非空、总配比 [99.0, 101.0]、温度 [30.0, 180.0]
            IF recipe[selSlot].recipeID <> 0
               AND recipe[selSlot].totalRatio >= 99.0
               AND recipe[selSlot].totalRatio <= 101.0
               AND recipe[selSlot].temperature >= 30.0
               AND recipe[selSlot].temperature <= 180.0 THEN
                valid := TRUE;
                loadedID := recipe[selSlot].recipeID;
            ELSE
                valid := FALSE;
                loadedID := 0;
            END_IF
        ELSE
            valid := FALSE;
            loadedID := 0;
        END_IF
    END_IF
    // 无上升沿时，valid 和 loadedID 保持不变
END_IF
// running 为 TRUE 时，valid 和 loadedID 保持不变

// 更新上一周期命令状态，用于上升沿检测
prev_loadCmd := loadCmd;

END_FUNCTION_BLOCK