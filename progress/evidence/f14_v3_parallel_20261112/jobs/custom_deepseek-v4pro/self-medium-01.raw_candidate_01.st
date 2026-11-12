FUNCTION_BLOCK FB
VAR_INPUT
    recipe : ARRAY[1..8] OF ST_Recipe;   // 配方槽位 1..8，槽位 recipeID=0 表示空
    selSlot : INT;                        // 操作员选中的槽位，合法范围 1..8
    loadCmd : BOOL;                       // 装载命令（上升沿触发一次装载）
    running : BOOL;                       // 当前是否处于生产状态
END_VAR
VAR_OUTPUT
    valid : BOOL;                         // 配方校验通过
    loadedID : INT;                       // 已装载的配方号，无配方时为 0
END_VAR
VAR
    prevLoadCmd  : BOOL;                  // 上一扫描周期的 loadCmd
    prevValid    : BOOL;                  // 上一扫描周期的 valid 输出
    prevLoadedID : INT;                   // 上一扫描周期的 loadedID 输出
    edge         : BOOL;                  // loadCmd 上升沿标志
    slotIndex    : INT;                   // 合法的槽位下标
    slotRecipe   : ST_Recipe;             // 当前选中的配方结构体
    ratioOK      : BOOL;                  // totalRatio 是否在合法区间
    tempOK       : BOOL;                  // temperature 是否在合法区间
END_VAR

    // 计算装载命令的上升沿
    edge := loadCmd AND NOT prevLoadCmd;

    IF running THEN
        // 生产状态：保持上一拍输出，包括刚进入生产的第一拍
        valid := prevValid;
        loadedID := prevLoadedID;
    ELSIF edge THEN
        // 非生产状态且检测到装载命令上升沿
        // 检查槽位是否越界
        IF (selSlot < 1) OR (selSlot > 8) THEN
            // 越界：判为非法，且不得访问数组外内存
            valid := FALSE;
            loadedID := 0;
        ELSE
            // 合法槽位
            slotIndex := selSlot;
            slotRecipe := recipe[slotIndex];

            // 检查槽位是否为空
            IF slotRecipe.recipeID = 0 THEN
                // 空槽：非法
                valid := FALSE;
                loadedID := 0;
            ELSE
                // 检查总配比和温度
                ratioOK := (slotRecipe.totalRatio >= 99.0) AND (slotRecipe.totalRatio <= 101.0);
                tempOK  := (slotRecipe.temperature >= 30.0) AND (slotRecipe.temperature <= 180.0);

                IF ratioOK AND tempOK THEN
                    // 全部校验通过
                    valid := TRUE;
                    loadedID := slotRecipe.recipeID;
                ELSE
                    // 任一校验失败
                    valid := FALSE;
                    loadedID := 0;
                END_IF;
            END_IF;
        END_IF;
    ELSE
        // 无装载沿且未生产：保持上一拍输出
        valid := prevValid;
        loadedID := prevLoadedID;
    END_IF;

    // 更新历史状态
    prevLoadCmd  := loadCmd;
    prevValid    := valid;
    prevLoadedID := loadedID;
END_FUNCTION_BLOCK