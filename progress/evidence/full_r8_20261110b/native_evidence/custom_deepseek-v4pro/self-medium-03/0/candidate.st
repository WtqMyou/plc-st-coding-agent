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
    prevObstacle : BOOL := FALSE;
    prevMotorUp : BOOL := FALSE;
    prevMotorDown : BOOL := FALSE;
    prevErrorFlag : BOOL := FALSE;
    risingOpen : BOOL;
    risingClose : BOOL;
    risingBoth : BOOL;
END_VAR

// 计算上升沿
risingOpen := openBtn AND NOT prevOpenBtn;
risingClose := closeBtn AND NOT prevCloseBtn;
risingBoth := (openBtn AND closeBtn) AND NOT (prevOpenBtn AND prevCloseBtn);

// 故障标志计算（S14）
errorFlag := obstacle OR (prevErrorFlag AND NOT risingBoth);

// 电机输出计算（S12、S13）
motorUp := (NOT obstacle AND NOT openLimit AND
            (prevMotorUp OR
             (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag AND
              risingOpen AND NOT closeBtn)));

motorDown := (NOT obstacle AND NOT closeLimit AND
              (prevMotorDown OR
               (NOT prevMotorUp AND NOT prevMotorDown AND NOT prevErrorFlag AND
                risingClose AND NOT openBtn)));

// 更新历史值
prevOpenBtn := openBtn;
prevCloseBtn := closeBtn;
prevObstacle := obstacle;
prevMotorUp := motorUp;
prevMotorDown := motorDown;
prevErrorFlag := errorFlag;

END_FUNCTION_BLOCK