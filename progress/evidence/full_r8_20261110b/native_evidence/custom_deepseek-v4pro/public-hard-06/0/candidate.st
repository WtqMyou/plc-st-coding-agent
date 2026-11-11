FUNCTION_BLOCK FB
VAR_INPUT
    Mode: BOOL;
    ForwardButton: BOOL;
    ReverseButton: BOOL;
    SensorFeed: BOOL;
    SensorWash: BOOL;
    SensorWeight: BOOL;
    SensorFiring: BOOL;
    SensorOutput: BOOL;
    washComplete: BOOL;
    weightComplete: BOOL;
    weight: REAL;
    firingComplete: BOOL;
END_VAR
VAR_OUTPUT
    MotorForward: BOOL;
    MotorReverse: BOOL;
    kick: BOOL;
    CompletionLight: BOOL;
    firingTemp: REAL := 0.0;
END_VAR
VAR
    autoState: INT := 0;
END_VAR

IF Mode THEN
    (* 自动模式 *)
    MotorForward := FALSE;
    MotorReverse := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;

    CASE autoState OF
        0: (* 空闲，等待上料 *)
            IF SensorFeed THEN
                autoState := 1; (* 移动至清洗 *)
                MotorForward := TRUE;
            END_IF

        1: (* 移动至清洗站 *)
            MotorForward := TRUE;
            IF SensorWash THEN
                autoState := 2; (* 到达清洗 *)
                MotorForward := FALSE;
            END_IF

        2: (* 在清洗站 *)
            IF washComplete THEN
                autoState := 3; (* 移动至称重 *)
                MotorForward := TRUE;
            END_IF

        3: (* 移动至称重站 *)
            MotorForward := TRUE;
            IF SensorWeight THEN
                autoState := 4; (* 到达称重 *)
                MotorForward := FALSE;
            END_IF

        4: (* 在称重站 *)
            IF weightComplete THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    (* 合格 *)
                    firingTemp := 500.0 + (weight - 100.0) * 0.5;
                    autoState := 6; (* 移动至烧结 *)
                    MotorForward := TRUE;
                ELSE
                    (* 不合格，发出剔除脉冲 *)
                    kick := TRUE;
                    autoState := 5; (* 等待剔除完成 *)
                END_IF
            END_IF

        5: (* 等待剔除完成 *)
            IF NOT SensorWeight THEN
                autoState := 0; (* 回到空闲 *)
            END_IF

        6: (* 移动至烧结站 *)
            MotorForward := TRUE;
            IF SensorFiring THEN
                autoState := 7; (* 到达烧结 *)
                MotorForward := FALSE;
            END_IF

        7: (* 在烧结站 *)
            IF firingComplete THEN
                autoState := 8; (* 移动至成品 *)
                MotorForward := TRUE;
            END_IF

        8: (* 移动至成品站 *)
            MotorForward := TRUE;
            IF SensorOutput THEN
                autoState := 9; (* 到达成品 *)
                MotorForward := FALSE;
                CompletionLight := TRUE;
            END_IF

        9: (* 在成品站 *)
            CompletionLight := TRUE;
            IF NOT SensorOutput THEN
                CompletionLight := FALSE;
                autoState := 0; (* 产品被取走，回到空闲 *)
            END_IF
    END_CASE
ELSE
    (* 手动模式 *)
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    kick := FALSE;
    CompletionLight := FALSE;
END_IF

END_FUNCTION_BLOCK