FUNCTION_BLOCK FB
VAR_INPUT
    demand : INT;
    runHours : ARRAY[1..5] OF LINT;
    rotated : BOOL;
END_VAR
VAR_OUTPUT
    leadPump : INT;
    lagPump : INT;
    runningCount : INT;
END_VAR
VAR
    prevLeadPump : INT := 0;
    prevLagPump : INT := 0;
    prevRunningCount : INT := 0;
    clampedDemand : INT;
    minPump : INT;
    i : INT;
END_VAR

// 裁剪需求
IF demand < 0 THEN
    clampedDemand := 0;
ELSIF demand > 5 THEN
    clampedDemand := 5;
ELSE
    clampedDemand := demand;
END_IF;

runningCount := clampedDemand;

// 计算全场最短工时泵（工时，泵号）最小
minPump := 1;
FOR i := 2 TO 5 DO
    IF (runHours[i] < runHours[minPump]) OR (runHours[i] = runHours[minPump] AND i < minPump) THEN
        minPump := i;
    END_IF;
END_FOR;

// 主泵选择
IF clampedDemand = 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSE
    // 需求 > 0
    IF prevLeadPump = 0 THEN
        // 初选
        leadPump := minPump;
    ELSE
        // 已有主泵
        IF rotated AND (runHours[prevLeadPump] - runHours[minPump] > 50) THEN
            leadPump := minPump;
        ELSE
            leadPump := prevLeadPump;
        END_IF;
    END_IF;

    // 备泵选择
    IF clampedDemand < 2 THEN
        lagPump := 0;
    ELSE
        // 需求 >= 2
        IF (leadPump <> prevLeadPump) OR (clampedDemand > prevRunningCount) THEN
            // 重新选择备泵（排除当前主泵）
            lagPump := 0;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF lagPump = 0 THEN
                        lagPump := i;
                    ELSE
                        IF (runHours[i] < runHours[lagPump]) OR (runHours[i] = runHours[lagPump] AND i < lagPump) THEN
                            lagPump := i;
                        END_IF;
                    END_IF;
                END_IF;
            END_FOR;
        ELSE
            lagPump := prevLagPump;
        END_IF;
    END_IF;
END_IF;

// 更新上一拍状态
prevLeadPump := leadPump;
prevLagPump := lagPump;
prevRunningCount := runningCount;

END_FUNCTION_BLOCK