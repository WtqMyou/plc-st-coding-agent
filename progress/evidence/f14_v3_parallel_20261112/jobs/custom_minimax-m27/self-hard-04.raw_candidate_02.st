FUNCTION_BLOCK FB
VAR_INPUT
    demand   : INT;
    runHours : ARRAY[1..5] OF LINT;
    rotated  : BOOL;
END_VAR
VAR_OUTPUT
    leadPump     : INT := 0;
    lagPump      : INT := 0;
    runningCount : INT := 0;
END_VAR
VAR
    prevDemand     : INT  := -1;
    prevLead       : INT  := 0;
    prevLag        : INT  := 0;
    prevRunning    : INT  := 0;
    firstPositive  : BOOL := FALSE;
END_VAR
VAR_TEMP
    i           : INT;
    minHours    : LINT;
    minIdx      : INT;
    minHours2   : LINT;
    minIdx2     : INT;
    adjDemand   : INT;
    leadChanged : BOOL;
    runInc      : BOOL;
END_VAR

// ── 裁剪需求台数 ──────────────────────────────────────────────────
IF demand < 0 THEN
    adjDemand := 0;
ELSIF demand > 5 THEN
    adjDemand := 5;
ELSE
    adjDemand := demand;
END_IF;

// ── 首次调用：初始化 prevDemand ──────────────────────────────────
IF prevDemand = -1 THEN
    prevDemand := adjDemand;
END_IF;

// ── 需求为 0：清空主备 ───────────────────────────────────────────
IF adjDemand = 0 THEN
    leadPump     := 0;
    lagPump      := 0;
    runningCount := 0;
    prevLead     := 0;
    prevLag      := 0;
    prevRunning  := 0;
    firstPositive := FALSE;
    prevDemand    := 0;
    RETURN;
END_IF;

// ── 主泵选择 ──────────────────────────────────────────────────────
// 初始选择：首次正需求
IF firstPositive THEN
    minHours := runHours[1];
    minIdx   := 1;
    FOR i := 2 TO 5 DO
        IF runHours[i] < minHours OR (runHours[i] = minHours AND i < minIdx) THEN
            minHours := runHours[i];
            minIdx   := i;
        END_IF;
    END_FOR;
    leadPump := minIdx;
// 迟滞换主：轮换请求有效 且 原主泵工时比全场最短严格多 50h 以上
ELSIF rotated AND prevLead <> 0 THEN
    minHours := runHours[1];
    minIdx   := 1;
    FOR i := 2 TO 5 DO
        IF runHours[i] < minHours OR (runHours[i] = minHours AND i < minIdx) THEN
            minHours := runHours[i];
            minIdx   := i;
        END_IF;
    END_FOR;
    IF runHours[prevLead] - minHours > 50 THEN
        leadPump := minIdx;
    ELSE
        leadPump := prevLead;
    END_IF;
ELSE
    leadPump := prevLead;
END_IF;

// ── 辅助标记 ──────────────────────────────────────────────────────
leadChanged := (leadPump <> prevLead);
runInc      := (adjDemand > prevRunning);

// ── 备泵选择（仅「初选、换主、运行台数上升」时重选）──────────────
IF adjDemand >= 2 THEN
    IF lagPump = 0 OR leadChanged OR runInc THEN
        minHours2 := LINT#16#7FFFFFFFFFFFFFFF;
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
        lagPump := prevLag;
    END_IF;
ELSE
    lagPump := 0;
END_IF;

// ── 运行台数 & 状态快照 ──────────────────────────────────────────
runningCount  := adjDemand;
firstPositive := FALSE;
prevLead      := leadPump;
prevLag       := lagPump;
prevRunning   := runningCount;
prevDemand    := adjDemand;
END_FUNCTION_BLOCK