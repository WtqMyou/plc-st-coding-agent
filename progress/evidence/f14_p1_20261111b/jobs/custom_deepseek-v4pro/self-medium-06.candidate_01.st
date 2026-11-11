FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    resetBtn : BOOL;
    sensorValid : BOOL;
    setpoint : REAL;
    temperature : REAL;
    scanSeconds : REAL;
    bias : REAL;
END_VAR
VAR_OUTPUT
    power : REAL;
    correction : REAL;
    fault : BOOL;
END_VAR
VAR
    ePrev : REAL;
    histValid : BOOL;
    lastResetBtn : BOOL;
END_VAR
VAR_TEMP
    e : REAL;
    de : REAL;
    x : REAL;
    y : REAL;
    resetRising : BOOL;
END_VAR

BEGIN
    -- 计算误差
    e := setpoint - temperature;
    
    -- 计算故障
    fault := NOT sensorValid OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
    
    -- 检测复位上升沿
    resetRising := resetBtn AND NOT lastResetBtn;
    
    IF (NOT enable OR fault OR resetRising) THEN
        -- 故障、停用或复位上升沿：输出归零，清除历史
        power := 0.0;
        correction := 0.0;
        ePrev := 0.0;
        histValid := FALSE;
    ELSE
        -- 正常模糊计算
        IF histValid THEN
            de := (e - ePrev) / scanSeconds;
        ELSE
            de := 0.0;  -- 首拍或历史被清除后恢复首拍
        END_IF;
        
        x := LIMIT(-1.0, e / 10.0, 1.0);
        y := LIMIT(-1.0, de / 2.0, 1.0);
        
        -- 九规则重心法等价于 20*x + 10*y
        correction := 20.0 * x + 10.0 * y;
        
        power := LIMIT(0.0, bias + correction, 100.0);
        
        ePrev := e;
        histValid := TRUE;
    END_IF;
    
    -- 更新上一周期复位按钮状态
    lastResetBtn := resetBtn;
END_FUNCTION_BLOCK