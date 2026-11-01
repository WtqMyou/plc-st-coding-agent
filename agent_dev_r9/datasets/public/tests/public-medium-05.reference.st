FUNCTION_BLOCK FB
VAR_INPUT
    Mode : BOOL;
    ForwardButton : BOOL;
    ReverseButton : BOOL;
    SensorA : BOOL;
    SensorB : BOOL;
    SensorC : BOOL;
    ButtonA : BOOL;
    ButtonB : BOOL;
    ButtonC : BOOL;
END_VAR
VAR_OUTPUT
    MotorForward : BOOL;
    MotorReverse : BOOL;
    CompletionLight : BOOL;
END_VAR
VAR
    step : INT;
END_VAR

(* R2: 正反转互锁，先无条件清零，任何分支都不允许两个方向同时输出 *)
MotorForward := FALSE;
MotorReverse := FALSE;
CompletionLight := FALSE;

IF Mode THEN
    (* R3: 自动模式按 A -> B -> C 顺序推进；
       0=等待 A，1=去 B，2=等待 B，3=去 C，4=等待 C，5=已完成 *)
    CASE step OF
        0:
            (* 必须"产品在 A（SensorA）且工位 A 加工完成（ButtonA）"才起步 *)
            IF SensorA AND ButtonA THEN
                step := 1;
                MotorForward := TRUE;
            END_IF
        1:
            (* 去 B 途中正转；B 工位传感器一到就立即停，进入等待 B *)
            MotorForward := TRUE;
            IF SensorB THEN
                MotorForward := FALSE;
                step := 2;
            END_IF
        2:
            IF SensorB AND ButtonB THEN
                step := 3;
                MotorForward := TRUE;
            END_IF
        3:
            MotorForward := TRUE;
            IF SensorC THEN
                MotorForward := FALSE;
                step := 4;
            END_IF
        4:
            (* 产品到 C 且工位 C 加工完成 -> 完成灯亮 *)
            IF SensorC AND ButtonC THEN
                CompletionLight := TRUE;
                step := 5;
            END_IF
        5:
            (* 产品被取走（SensorC 不再检测）即灭灯并回到初始等待下一件 *)
            CompletionLight := SensorC;
            IF NOT SensorC THEN
                step := 0;
            END_IF
    ELSE
        step := 0;
    END_CASE
ELSE
    (* R2: 手动模式，自动流程作废；正反转按钮互锁，两个同时按下则都不动作 *)
    step := 0;
    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
    END_IF
    IF ReverseButton AND NOT ForwardButton THEN
        MotorReverse := TRUE;
    END_IF
END_IF
END_FUNCTION_BLOCK
