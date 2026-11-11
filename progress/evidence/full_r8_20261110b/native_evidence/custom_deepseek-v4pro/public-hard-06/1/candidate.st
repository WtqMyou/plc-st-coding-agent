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
    firingTemp: REAL;
END_VAR
VAR
    autoState: INT := 0;
    prevMode: BOOL := FALSE;
END_VAR

(* 模式上升沿检测，重置自动状态机 *)
IF Mode AND NOT prevMode THEN
    autoState := 0;
END_IF
prevMode := Mode;

IF Mode THEN
    (* 自动模式初始输出 *)
    MotorForward := FALSE;
    MotorReverse := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;

    CASE autoState OF
        0: (* 空闲等待上料 *)
            IF SensorFeed THEN
                autoState := 1;
                MotorForward := TRUE;
            END_IF

        1: (* 移动至清洗站 *)
            IF SensorWash THEN
                autoState := 2;
                MotorForward := FALSE;
            ELSE
                MotorForward := TRUE;
            END_IF

        2: (* 在清洗站等待清洗完成 *)
            MotorForward := FALSE;
            IF washComplete THEN
                autoState := 3;
                MotorForward := TRUE;
            END_IF

        3: (* 移动至称重站 *)
            IF SensorWeight THEN
                autoState := 4;
                MotorForward := FALSE;
            ELSE
                MotorForward := TRUE;
            END_IF

        4: (* 在称重站等待称重完成 *)
            MotorForward := FALSE;
            IF weightComplete THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    firingTemp := 500.0 + (weight - 100.0) * 0.5;
                    autoState := 6;
                    MotorForward := TRUE;
                ELSE
                    kick := TRUE;
                    autoState := 5;
                END_IF
            END_IF

        5: (* 等待剔除完成 *)
            MotorForward := FALSE;
            IF NOT SensorWeight THEN
                autoState := 0;
            END_IF

        6: (* 移动至烧结站 *)
            IF SensorFiring THEN
                autoState := 7;
                MotorForward := FALSE;
            ELSE
                MotorForward := TRUE;
            END_IF

        7: (* 在烧结站等待烧结完成 *)
            MotorForward := FALSE;
            IF firingComplete THEN
                autoState := 8;
                MotorForward := TRUE;
            END_IF

        8: (* 移动至成品站 *)
            IF SensorOutput THEN
                autoState := 9;
                MotorForward := FALSE;
                CompletionLight := TRUE;
            ELSE
                MotorForward := TRUE;
            END_IF

        9: (* 在成品站 *)
            MotorForward := FALSE;
            CompletionLight := TRUE;
            IF NOT SensorOutput THEN
                CompletionLight := FALSE;
                autoState := 0;
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