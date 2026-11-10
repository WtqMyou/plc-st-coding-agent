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
    prevBothBtn : BOOL := FALSE;
    prevMotorUp : BOOL := FALSE;
    prevMotorDown : BOOL := FALSE;
    prevErrorFlag : BOOL := FALSE;
    risingOpen : BOOL;
    risingClose : BOOL;
    risingBoth : BOOL;
END_VAR

// 计算输入上升沿
risingOpen := openBtn AND NOT prevOpenBtn;
risingClose := closeBtn AND NOT prevCloseBtn;
risingBoth := (openBtn AND closeBtn) AND NOT prevBothBtn;

// 故障锁存与复位
errorFlag := obstacle OR (prevErrorFlag AND NOT risingBoth);

// 电机命令
motorUp := NOT obstacle AND NOT openLimit AND
           (prevMotorUp OR
            (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag AND risingOpen AND NOT closeBtn));

motorDown := NOT obstacle AND NOT closeLimit AND
            (prevMotorDown OR
             (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag AND risingClose AND NOT openBtn));

// 更新历史状态
prevOpenBtn := openBtn;
prevCloseBtn := closeBtn;
prevBothBtn := openBtn AND closeBtn;
prevMotorUp := motorUp;
prevMotorDown := motorDown;
prevErrorFlag := errorFlag;

END_FUNCTION_BLOCK