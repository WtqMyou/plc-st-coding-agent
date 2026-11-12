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
    valid : BOOL;
    loadedID : INT;
END_VAR
VAR
    prevLoadCmd  : BOOL;
    prevValid    : BOOL;
    prevLoadedID : INT;
    edge         : BOOL;
    slotIndex    : INT;
    slotRecipe   : ST_Recipe;
    ratioOK      : BOOL;
    tempOK       : BOOL;
END_VAR

    edge := loadCmd AND NOT prevLoadCmd;

    IF running THEN
        (* 生产状态：保持上一拍输出，包括刚进入生产的第一拍 *)
        valid := prevValid;
        loadedID := prevLoadedID;
    ELSIF edge THEN
        (* 非生产状态且检测到装载命令上升沿 *)
        IF (selSlot < 1) OR (selSlot > 8) THEN
            (* 槽位越界：判为非法，不访问数组 *)
            valid := FALSE;
            loadedID := 0;
        ELSE
            slotIndex := selSlot;
            slotRecipe := recipe[slotIndex];

            IF slotRecipe.recipeID = 0 THEN
                (* 空槽：非法 *)
                valid := FALSE;
                loadedID := 0;
            ELSE
                ratioOK := (slotRecipe.totalRatio >= 99.0) AND (slotRecipe.totalRatio <= 101.0);
                tempOK  := (slotRecipe.temperature >= 30.0) AND (slotRecipe.temperature <= 180.0);

                IF ratioOK AND tempOK THEN
                    valid := TRUE;
                    loadedID := slotRecipe.recipeID;
                ELSE
                    valid := FALSE;
                    loadedID := 0;
                END_IF;
            END_IF;
        END_IF;
    ELSE
        (* 无装载沿且未生产：保持上一拍输出 *)
        valid := prevValid;
        loadedID := prevLoadedID;
    END_IF;

    (* 更新历史状态 *)
    prevLoadCmd  := loadCmd;
    prevValid    := valid;
    prevLoadedID := loadedID;
END_FUNCTION_BLOCK