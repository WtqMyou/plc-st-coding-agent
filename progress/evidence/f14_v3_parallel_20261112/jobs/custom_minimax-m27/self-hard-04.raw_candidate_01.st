FUNCTION_BLOCK FB
VAR_INPUT
    demand     : INT;
    runHours   : ARRAY[1..5] OF LINT;
    rotated    : BOOL;
END_VAR
VAR_OUTPUT
    leadPump     : INT := 0;
    lagPump      : INT := 0;
    runningCount : INT := 0;
END_VAR
VAR
    prevDemand   : INT  := 0;
    prevLead     : INT  := 0;
    prevLag      : INT  := 0;
    prevRunning  : INT  := 0;
END_VAR

VAR_TEMP
    i            : INT;
    minHours     : LINT;
    minIdx       : INT;
    minHours2    : LINT;
    minIdx2      : INT;
    adjDemand    : INT;
    leadChanged  : BOOL;
    runInc       : BOOL;
END_VAR

// ── 1. 裁剪需求台数 ──────────────────────────────────────────────
IF demand < 0 THEN
    adjDemand := 0;
ELSIF demand > 5 THEN
    adjDemand := 5;
ELSE
    adjDemand := demand;
END_IF;

// ── 2. 需求归零 → 立即清除主备 ───────────────────────────────────
IF adjDemand = 0 THEN
    leadPump     := 0;
    lagPump      := 0;
    runningCount := 0;
    prevDemand   := 0;
    prevLead     := 0;
    prevLag      := 0;
    prevRunning  := 0;
    RETURN;
END_IF;

// ── 3. 主泵选择 ──────────────────────────────────────────────────
// 初选：上次主泵为空（需求从 0 恢复）
IF prevLead = 0 THEN
    minHours := runHours[1];
    minIdx   := 1;
    FOR i := 2 TO 5 DO
        IF runHours[i] < minHours OR (runHours[i] = minHours AND i < minIdx) THEN
            minHours := runHours[i];
            minIdx   := i;
        END_IF;
    END_FOR;
    leadPump := minIdx;
// 轮换请求有效且迟滞条件满足时换主
ELSIF rotated THEN
    // 找全场（工时，泵号）最小者
    minHours := runHours[1];
    minIdx   := 1;
    FOR i := 2 TO 5 DO
        IF runHours[i] < minHours OR (runHours[i] = minHours AND i < minIdx) THEN
            minHours := runHours[i];
            minIdx   := i;
        END_IF;
    END_FOR;
    // 迟滞：本拍主泵工时比最短工时严格多 50h 以上
    IF runHours[prevLead] - minHours > 50 THEN
        leadPump := minIdx;
    ELSE
        leadPump := prevLead;
    END_IF;
ELSE
    // 无请求且有主泵 → 保持
    leadPump := prevLead;
END_IF;

// ── 4. 辅助标记 ──────────────────────────────────────────────────
leadChanged := (leadPump <> prevLead);
runInc      := (adjDemand > prevRunning);

// ── 5. 备泵选择（仅在「初选、换主、运行台数上升」时重选）─────────
IF adjDemand >= 2 THEN
    // 初选：lagPump 仍为 0
    // 换主或台数上升：lagPump 需要刷新
    IF lagPump = 0 OR leadChanged OR runInc THEN
        // 找除主泵外（工时，泵号）最小者
        minHours2 := LINT#16#7FFFFFFFFFFFFFFF;  // 最大值
        minIdx2   := 0;
        FOR i := 1 TO 5 DO
            IF i <> leadPump THEN
                IF runHours[i] < minHours2 OR (runHours[i] = minHours2 AND i < minIdx2) THEN
                    minHours2 := runHours[i];
                    minIdx2   := i;
                END_IF;
            END_IF;
        END_FOR;
        lagPump := minIdx2;
    ELSE
        // 主泵未变且台数未升 → 保持原备泵（S9 约束）
        lagPump := prevLag;
    END_IF;
ELSE
    // 需求 1 台 → 无备泵
    lagPump := 0;
END_IF;

// ── 6. 运行台数 & 状态快照 ───────────────────────────────────────
runningCount := adjDemand;
prevDemand   := adjDemand;
prevLead     := leadPump;
prevLag      := lagPump;
prevRunning  := runningCount;
END_FUNCTION_BLOCK