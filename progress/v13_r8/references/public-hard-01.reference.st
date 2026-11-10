(*
    public-hard-01  Material Proportioning Process Control
    参考解：单个 FUNCTION_BLOCK。接口名与数据类型严格照抄 variables。

    平台说明（公共题制作约定 §7）：
      * 无 TON / R_TRIG，按钮的上升沿用显式边沿
            e := btn AND NOT prev;  prev := btn;
        在扫描末尾统一滚动 prev，避免同拍重复触发。
      * "液位达到 N cm" 用 levelSensor >= N 判断（液位单调上升的语义）。
      * 时间类原语里没有可用的定时器，本题流程全部由 levelSensor / 完成信号推进。

    本文件用 (* R1: ... *) 形式标注需求编号，逐条对应 requirements。
*)
FUNCTION_BLOCK FB_MaterialProportioning
VAR_INPUT
    estop : BOOL;             (* R1 急停：FALSE = 触发 *)
    opeMode : BOOL;           (* R2/R4 运行方式：FALSE = 手动，TRUE = 自动 *)
    valveAStart : BOOL;       (* 手动按钮（上升沿启停） *)
    valveBStart : BOOL;
    valveCStart : BOOL;
    valveDStart : BOOL;
    mixMotorStart : BOOL;
    autoStart : BOOL;         (* 自动流程启动按钮（上升沿） *)
    processMode : BOOL;       (* R5 FALSE = 直接混合；TRUE = 先进 C 到 100cm 再混合 *)
    levelSensor : INT;        (* 液位传感器，单位 cm *)
    mixMotorComplete : BOOL;  (* R6 混合完成信号 *)
END_VAR
VAR_OUTPUT
    valveARun : BOOL;
    valveBRun : BOOL;
    valveCRun : BOOL;
    valveDRun : BOOL;
    mixMotorRun : BOOL;
END_VAR
VAR
    (* 自动流程步序：0 空闲 / 10 进料 A / 20 进料 B / 35 进料 C / 40 混合 / 50 完成 *)
    state : INT;
    (* 各按钮与运行方式上一拍的值（显式边沿用） *)
    prevAutoStart : BOOL;
    prevValveAStart : BOOL;
    prevValveBStart : BOOL;
    prevValveCStart : BOOL;
    prevValveDStart : BOOL;
    prevMixMotorStart : BOOL;
    prevOpeMode : BOOL;
    (* 手动模式下五个设备的启停记忆 *)
    manA : BOOL;
    manB : BOOL;
    manC : BOOL;
    manD : BOOL;
    manMix : BOOL;
END_VAR

(* R1: 急停最高优先级——estop=FALSE 时所有设备立即停机，
   并复位自动流程与手动记忆；急停解除后不会自动续跑，必须重新启动。 *)
IF NOT estop THEN
    state := 0;
    manA := FALSE;
    manB := FALSE;
    manC := FALSE;
    manD := FALSE;
    manMix := FALSE;
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

(* R2: 手动模式——五个设备各自由对应按钮的上升沿翻转（启/停）。
   R3: 只认上升沿：按住不放不会反复翻转；释放后保持当前状态。 *)
ELSIF NOT opeMode THEN
    (* 从自动切到手动的那一拍：放弃自动流程，手动记忆全部复位（需求未规定，
       取最安全侧，见文件末尾"需求未覆盖处"说明）。 *)
    IF prevOpeMode THEN
        state := 0;
        manA := FALSE;
        manB := FALSE;
        manC := FALSE;
        manD := FALSE;
        manMix := FALSE;
    END_IF
    IF valveAStart AND NOT prevValveAStart THEN
        manA := NOT manA;
    END_IF
    IF valveBStart AND NOT prevValveBStart THEN
        manB := NOT manB;
    END_IF
    IF valveCStart AND NOT prevValveCStart THEN
        manC := NOT manC;
    END_IF
    IF valveDStart AND NOT prevValveDStart THEN
        manD := NOT manD;
    END_IF
    IF mixMotorStart AND NOT prevMixMotorStart THEN
        manMix := NOT manMix;
    END_IF
    valveARun := manA;
    valveBRun := manB;
    valveCRun := manC;
    valveDRun := manD;
    mixMotorRun := manMix;

(* R4/R5/R6: 自动模式——按工艺步序推进设备，手动按钮被忽略。 *)
ELSE
    (* 刚进入自动模式：自动流程从头开始，手动残留输出全部关断。 *)
    IF NOT prevOpeMode THEN
        state := 0;
        valveARun := FALSE;
        valveBRun := FALSE;
        valveCRun := FALSE;
        valveDRun := FALSE;
        mixMotorRun := FALSE;
    END_IF

    CASE state OF
        0:  (* 空闲：等待 autoStart 上升沿 *)
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            (* R4: 按 autoStart 启动自动流程，先开阀 A *)
            IF autoStart AND NOT prevAutoStart THEN
                state := 10;
                valveARun := TRUE;
            END_IF

        10: (* 进料 A：液位到 50cm 关 A、开 B *)
            valveARun := TRUE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            IF levelSensor >= 50 THEN
                valveARun := FALSE;
                valveBRun := TRUE;
                state := 20;
            END_IF

        20: (* 进料 B：液位到 80cm 关 B；随后按 processMode 决定下一步 *)
            valveARun := FALSE;
            valveBRun := TRUE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            IF levelSensor >= 80 THEN
                valveBRun := FALSE;
                IF processMode THEN
                    (* R5(true): 先开 C 继续进料到 100cm *)
                    valveCRun := TRUE;
                    state := 35;
                ELSE
                    (* R5(false): 不进 C，直接启动混合电机 *)
                    mixMotorRun := TRUE;
                    state := 40;
                END_IF
            END_IF

        35: (* 进料 C：液位到 100cm 关 C、启动混合电机 *)
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := TRUE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            IF levelSensor >= 100 THEN
                valveCRun := FALSE;
                mixMotorRun := TRUE;
                state := 40;
            END_IF

        40: (* 混合中：收到混合完成信号 → 停电机、开 D、流程结束 *)
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := TRUE;
            IF mixMotorComplete THEN
                mixMotorRun := FALSE;
                valveDRun := TRUE;
                state := 50;
            END_IF

        50: (* 完成：D 保持开启把料送出；再次 autoStart 开始新一周期 *)
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := TRUE;
            mixMotorRun := FALSE;
            IF autoStart AND NOT prevAutoStart THEN
                valveDRun := FALSE;
                valveARun := TRUE;
                state := 10;
            END_IF
    END_CASE
END_IF

(* 边沿记忆统一在扫描末尾滚动（顺序不可提前，见约定 §7）。 *)
prevAutoStart := autoStart;
prevValveAStart := valveAStart;
prevValveBStart := valveBStart;
prevValveCStart := valveCStart;
prevValveDStart := valveDStart;
prevMixMotorStart := mixMotorStart;
prevOpeMode := opeMode;

(*
  需求未覆盖处的取舍（均为最安全侧，且已由 test_cases 覆盖其行为）：
  1) 运行方式切换：自动→手动或手动→自动时，当前流程被中止、输出全部关断，
     不会在切换后残留上一模式的设备动作；自动模式要从步序 0 重新 autoStart。
  2) 自动流程进行中再次按 autoStart 被忽略（按键只对步序 0 / 50 有效），
     避免运行中反复重启流程。
  3) 自动完成后阀 D 保持开启（"open valve D, and the automatic process ends"），
     直到下一次 autoStart 开始新周期或急停触发。
  4) 步序 0 与各步都显式给全部输出赋值，保证同一扫描周期内输出不残留上一步的值。
*)
END_FUNCTION_BLOCK
