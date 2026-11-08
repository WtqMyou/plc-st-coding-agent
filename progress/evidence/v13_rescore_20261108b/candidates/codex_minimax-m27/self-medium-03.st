FUNCTION_BLOCK FB
VAR_INPUT
    openBtn   : BOOL;    // 开门按钮（上升沿有效）
    closeBtn  : BOOL;    // 关门按钮（上升沿有效）
    openLimit : BOOL;    // 开到位限位开关
    closeLimit: BOOL;    // 关到位限位开关
    obstacle  : BOOL;    // 防夹物体检测
END_VAR
VAR_OUTPUT
    motorUp   : BOOL;    // 电机上升（开门）输出
    motorDown : BOOL;    // 电机下降（关门）输出
    errorFlag : BOOL;    // 故障锁存（需人工复位后清除）
END_VAR
VAR
    state        : INT;      // 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT
    openBtnLast  : BOOL;     // 上次扫描的开门按钮状态
    closeBtnLast : BOOL;     // 上次扫描的关门按钮状态
END_VAR

// 初始化输出
motorUp   := FALSE;
motorDown := FALSE;

// 状态机
IF state = 0 THEN  // IDLE
    IF openBtn AND NOT openBtnLast AND NOT openLimit THEN
        state := 1;
    ELSIF closeBtn AND NOT closeBtnLast AND NOT closeLimit THEN
        state := 2;
    END_IF

ELSIF state = 1 THEN  // OPENING
    IF openLimit THEN
        state := 0;
    ELSIF obstacle THEN
        state := 3;
    END_IF

ELSIF state = 2 THEN  // CLOSING
    IF obstacle THEN
        state := 1;
    ELSIF closeLimit THEN
        state := 0;
    END_IF

ELSIF state = 3 THEN  // FAULT
    errorFlag := TRUE;
    IF openBtn AND closeBtn THEN
        state     := 0;
        errorFlag := FALSE;
    END_IF
END_IF

// 更新历史（周期末）
openBtnLast  := openBtn;
closeBtnLast := closeBtn;

// 互锁与输出生成
IF state = 3 THEN  // FAULT
    motorUp   := FALSE;
    motorDown := FALSE;
ELSIF state = 1 THEN  // OPENING
    motorUp   := TRUE;
    motorDown := FALSE;
ELSIF state = 2 THEN  // CLOSING
    motorUp   := FALSE;
    motorDown := TRUE;
ELSE  // IDLE
    motorUp   := FALSE;
    motorDown := FALSE;
END_IF

END_FUNCTION_BLOCK