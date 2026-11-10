FUNCTION_BLOCK FB
VAR_INPUT
    demand: INT;
    runHours: ARRAY[1..5] OF LINT;
    rotated: BOOL;
END_VAR
VAR_OUTPUT
    leadPump: INT;
    lagPump: INT;
    runningCount: INT;
END_VAR
VAR
    lastDemandClipped: INT := 0;
    lastLeadPump: INT := 0;
    lastLagPump: INT := 0;
    lastRunningCount: INT := 0;
    clippedDemand: INT;
    minPump: INT;
    i: INT;
END_VAR

// 裁剪需求
clippedDemand := demand;
IF clippedDemand < 0 THEN
    clippedDemand := 0;
END_IF;
IF clippedDemand > 5 THEN
    clippedDemand := 5;
END_IF;
runningCount := clippedDemand;

// 处理主泵和备泵
IF clippedDemand = 0 THEN
    // 需求为零：清空主备泵
    leadPump := 0;
    lagPump := 0;
ELSE
    // 正需求
    IF lastDemandClipped = 0 THEN
        // 初选主泵：全场（工时，泵号）最小
        minPump := 1;
        FOR i := 2 TO 5 DO
            IF runHours[i] < runHours[minPump] THEN
                minPump := i;
            ELSIF runHours[i] = runHours[minPump] AND i < minPump THEN
                minPump := i;
            END_IF;
        END_FOR;
        leadPump := minPump;
    ELSE
        // 已有主泵：默认保持
        leadPump := lastLeadPump;
        // 轮换请求处理
        IF rotated THEN
            // 计算全场最小泵
            minPump := 1;
            FOR i := 2 TO 5 DO
                IF runHours[i] < runHours[minPump] THEN
                    minPump := i;
                ELSIF runHours[i] = runHours[minPump] AND i < minPump THEN
                    minPump := i;
                END_IF;
            END_FOR;
            // 只有当前主泵工时比最小泵多严格超过50小时才换主
            IF runHours[lastLeadPump] - runHours[minPump] > 50 THEN
                leadPump := minPump;
            END_IF;
        END_IF;
    END_IF;

    // 备泵选择
    IF clippedDemand = 1 THEN
        lagPump := 0;
    ELSIF clippedDemand >= 2 THEN
        // 需要备泵，判断是否需重选
        IF (lastDemandClipped = 0) OR (leadPump <> lastLeadPump) OR (clippedDemand > lastDemandClipped) THEN
            // 选排除当前主泵后的最小泵
            IF leadPump <> 1 THEN
                minPump := 1;
            ELSE
                minPump := 2;
            END_IF;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF runHours[i] < runHours[minPump] THEN
                        minPump := i;
                    ELSIF runHours[i] = runHours[minPump] AND i < minPump THEN
                        minPump := i;
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := minPump;
        ELSE
            // 保持上拍备泵
            lagPump := lastLagPump;
        END_IF;
    ELSE
        lagPump := 0;
    END_IF;
END_IF;

// 更新历史状态
lastDemandClipped := clippedDemand;
lastLeadPump := leadPump;
lastLagPump := lagPump;
lastRunningCount := runningCount;

END_FUNCTION_BLOCK