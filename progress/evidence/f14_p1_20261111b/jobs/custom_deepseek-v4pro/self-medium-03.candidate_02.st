FUNCTION_BLOCK FB
VAR_INPUT
    openBtn : BOOL;
    closeBtn : BOOL;
    openLimit : BOOL;
    closeLimit : BOOL;
    obstacle : BOOL;
END_VAR
VAR_OUTPUT
    motorUp : BOOL;
    motorDown : BOOL;
    errorFlag : BOOL;
END_VAR
VAR
    prevOpenBtn : BOOL := FALSE;
    prevCloseBtn : BOOL := FALSE;
    prevBoth : BOOL := FALSE;
    prevMotorUp : BOOL := FALSE;
    prevMotorDown : BOOL := FALSE;
    prevErrorFlag : BOOL := FALSE;
    risingOpen : BOOL := FALSE;
    risingClose : BOOL := FALSE;
    currentBoth : BOOL := FALSE;
    risingBoth : BOOL := FALSE;
    state : INT := 0;
END_VAR

// 边沿检测
risingOpen := openBtn AND NOT prevOpenBtn;
risingClose := closeBtn AND NOT prevCloseBtn;
currentBoth := openBtn AND closeBtn;
risingBoth := currentBoth AND NOT prevBoth;

// 输出计算
motorUp := NOT obstacle AND NOT openLimit AND (prevMotorUp OR (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag AND risingOpen AND NOT closeBtn));

motorDown := NOT obstacle AND NOT closeLimit AND (prevMotorDown OR (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag AND risingClose AND NOT openBtn));

errorFlag := obstacle OR (prevErrorFlag AND NOT risingBoth);

// 状态更新
IF errorFlag THEN
    state := 3; // FAULT
ELSIF motorUp THEN
    state := 1; // OPENING
ELSIF motorDown THEN
    state := 2; // CLOSING
ELSE
    state := 0; // IDLE
END_IF;

// 更新 prev 变量
prevOpenBtn := openBtn;
prevCloseBtn := closeBtn;
prevBoth := currentBoth;
prevMotorUp := motorUp;
prevMotorDown := motorDown;
prevErrorFlag := errorFlag;

END_FUNCTION_BLOCK