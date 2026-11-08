FUNCTION_BLOCK FB
VAR_INPUT
    estop : BOOL;
    opeMode : BOOL;
    valveAStart : BOOL;
    valveBStart : BOOL;
    valveCStart : BOOL;
    valveDStart : BOOL;
    mixMotorStart : BOOL;
    autoStart : BOOL;
    processMode : BOOL;
    levelSensor : INT;
    mixMotorComplete : BOOL;
END_VAR
VAR_OUTPUT
    valveARun : BOOL;
    valveBRun : BOOL;
    valveCRun : BOOL;
    valveDRun : BOOL;
    mixMotorRun : BOOL;
END_VAR
VAR
    manValveA : BOOL := FALSE;
    manValveB : BOOL := FALSE;
    manValveC : BOOL := FALSE;
    manValveD : BOOL := FALSE;
    manMixMotor : BOOL := FALSE;
    autoStep : INT := 0;
    autoValveA : BOOL := FALSE;
    autoValveB : BOOL := FALSE;
    autoValveC : BOOL := FALSE;
    autoValveD : BOOL := FALSE;
    autoMixMotor : BOOL := FALSE;
    lastValveAStart : BOOL := FALSE;
    lastValveBStart : BOOL := FALSE;
    lastValveCStart : BOOL := FALSE;
    lastValveDStart : BOOL := FALSE;
    lastMixMotorStart : BOOL := FALSE;
    lastAutoStart : BOOL := FALSE;
    lastMixMotorComplete : BOOL := FALSE;
    lastOpeMode : BOOL := FALSE;
    valveAStartRising : BOOL;
    valveBStartRising : BOOL;
    valveCStartRising : BOOL;
    valveDStartRising : BOOL;
    mixMotorStartRising : BOOL;
    autoStartRising : BOOL;
    mixMotorCompleteRising : BOOL;
END_VAR

// 计算所有输入信号的上升沿
valveAStartRising := valveAStart AND NOT lastValveAStart;
valveBStartRising := valveBStart AND NOT lastValveBStart;
valveCStartRising := valveCStart AND NOT lastValveCStart;
valveDStartRising := valveDStart AND NOT lastValveDStart;
mixMotorStartRising := mixMotorStart AND NOT lastMixMotorStart;
autoStartRising := autoStart AND NOT lastAutoStart;
mixMotorCompleteRising := mixMotorComplete AND NOT lastMixMotorComplete;

// 急停或模式切换时，复位所有内部状态（手动记忆和自动步序）
IF (estop = FALSE) OR (opeMode <> lastOpeMode) THEN
    manValveA := FALSE;
    manValveB := FALSE;
    manValveC := FALSE;
    manValveD := FALSE;
    manMixMotor := FALSE;
    autoStep := 0;
    autoValveA := FALSE;
    autoValveB := FALSE;
    autoValveC := FALSE;
    autoValveD := FALSE;
    autoMixMotor := FALSE;
END_IF;

// 根据急停和模式设置输出
IF estop = TRUE THEN
    IF opeMode = FALSE THEN
        // 手动模式：按钮上升沿翻转对应输出
        IF valveAStartRising THEN
            manValveA := NOT manValveA;
        END_IF;
        IF valveBStartRising THEN
            manValveB := NOT manValveB;
        END_IF;
        IF valveCStartRising THEN
            manValveC := NOT manValveC;
        END_IF;
        IF valveDStartRising THEN
            manValveD := NOT manValveD;
        END_IF;
        IF mixMotorStartRising THEN
            manMixMotor := NOT manMixMotor;
        END_IF;

        valveARun := manValveA;
        valveBRun := manValveB;
        valveCRun := manValveC;
        valveDRun := manValveD;
        mixMotorRun := manMixMotor;
    ELSE
        // 自动模式
        IF autoStartRising THEN
            autoStep := 1;  // 进入FILL_A
            autoValveA := TRUE;
            autoValveB := FALSE;
            autoValveC := FALSE;
            autoValveD := FALSE;
            autoMixMotor := FALSE;
        END_IF;

        CASE autoStep OF
            0: // 空闲
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;

            1: // 填充A
                autoValveA := TRUE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;
                IF levelSensor >= 50 THEN
                    autoValveA := FALSE;
                    autoStep := 2;
                END_IF;

            2: // 填充B
                autoValveB := TRUE;
                autoValveA := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;
                IF levelSensor >= 80 THEN
                    autoValveB := FALSE;
                    IF processMode THEN
                        autoStep := 4; // 填充C
                    ELSE
                        autoStep := 3; // 混合
                    END_IF;
                END_IF;

            3: // 混合电机运行
                autoMixMotor := TRUE;
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                IF mixMotorCompleteRising THEN
                    autoMixMotor := FALSE;
                    autoValveD := TRUE;
                    autoStep := 5; // 出料
                END_IF;

            4: // 填充C（仅processMode=TRUE）
                autoValveC := TRUE;
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;
                IF levelSensor >= 100 THEN
                    autoValveC := FALSE;
                    autoStep := 3; // 混合
                END_IF;

            5: // 出料
                autoValveD := TRUE;
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoMixMotor := FALSE;
                // 等待新的autoStart上升沿，由外层处理

            ELSE
                // 非法状态，复位
                autoStep := 0;
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;
        END_CASE;

        valveARun := autoValveA;
        valveBRun := autoValveB;
        valveCRun := autoValveC;
        valveDRun := autoValveD;
        mixMotorRun := autoMixMotor;
    END_IF;
ELSE
    // 急停触发：所有输出停止
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;
END_IF;

// 更新历史值
lastValveAStart := valveAStart;
lastValveBStart := valveBStart;
lastValveCStart := valveCStart;
lastValveDStart := valveDStart;
lastMixMotorStart := mixMotorStart;
lastAutoStart := autoStart;
lastMixMotorComplete := mixMotorComplete;
lastOpeMode := opeMode;

END_FUNCTION_BLOCK