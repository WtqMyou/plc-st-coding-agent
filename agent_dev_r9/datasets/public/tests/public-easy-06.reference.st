(* 公开题 public-easy-06：Aeration Blower Delayed Start
   平台偏差（契约 §7，2026-10-24 实测）：TIME 字面量恒为 0、TIME 运算恒为 0，
   所以"5 秒启动延时"无法用 TIME 计时，改写为**扫描周期计数**：
   连续 5 个扫描周期满足条件才允许启动（1 拍 = 1 s）。用例按拍数断言。 *)
FUNCTION_BLOCK FB_AerationBlower
VAR_INPUT
    DO_LOW : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR
VAR_OUTPUT
    BLOWER_RUN : BOOL;
    AERATION_BLOWER_CYCLE_COUNT : UINT;
END_VAR
VAR
    delayCount : INT;   (* 连续满足"低氧且无急停"的拍数，5 拍到点 *)
    prevRun : BOOL;     (* 上一拍的运行命令，用于上升沿判据 *)
    initialized : BOOL;
END_VAR

(* R4: 上电初始化——风机 OFF、启动计数清零 *)
IF NOT initialized THEN
    initialized := TRUE;
    BLOWER_RUN := FALSE;
    AERATION_BLOWER_CYCLE_COUNT := 0;
    delayCount := 0;
    prevRun := FALSE;
END_IF

(* R1/R2: 启动延时门。条件是"低氧需求 AND 无急停"：
   满足则数拍（满 5 拍才置运行命令）；任一条件掉下来就立刻停机并复位计时，
   不管计时有没有完成——所以新的需求要重新等满 5 拍。 *)
IF DO_LOW AND AERATION_E_STOP_NC THEN
    IF delayCount < 5 THEN
        delayCount := delayCount + 1;
    END_IF
    IF delayCount >= 5 THEN
        BLOWER_RUN := TRUE;
    END_IF
ELSE
    delayCount := 0;
    BLOWER_RUN := FALSE;
END_IF

(* R3: 只在运行命令的 FALSE→TRUE 上升沿计一次数。
   顺序不能反：先用"本拍"和"上一拍"比较，最后才更新 prevRun。 *)
IF BLOWER_RUN AND NOT prevRun THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF
prevRun := BLOWER_RUN;

END_FUNCTION_BLOCK
