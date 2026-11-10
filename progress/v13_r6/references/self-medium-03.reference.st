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
    state : INT;
    openPrev : BOOL;
    closePrev : BOOL;
    openEdge : BOOL;
    closeEdge : BOOL;
END_VAR

(* 状态编码：0=IDLE 1=OPENING 2=CLOSING 3=FAULT *)
openEdge := openBtn AND NOT openPrev;
openPrev := openBtn;
closeEdge := closeBtn AND NOT closePrev;
closePrev := closeBtn;

(* 障碍优先于一切：无论哪个方向，立即停机 *)
IF obstacle THEN
    motorUp := FALSE;
    motorDown := FALSE;
    IF state <> 3 THEN
        IF state = 2 THEN
            state := 1;
        ELSE
            state := 3;
            errorFlag := TRUE;
        END_IF
    END_IF
ELSE
    (* 障碍解除后必须能重新启动：FAULT 只是"停着等"，不是永久锁死。
       这一段必须写在 ELSE 里——写进 IF obstacle 里面就成了"只有还挡着
       的时候才放行"，语义完全反了。
       但**不能在这里清 errorFlag**：清锁存和"允许动作"必须是同一件事，
       否则会出现"errorFlag 还亮着电机已经转起来"的中间状态，
       直接违反 S4（G(errorFlag -> !motorUp & !motorDown)）。
       所以锁存只在真正接受指令、状态从 IDLE 迁出时清除。 *)
    CASE state OF
        0:
            IF openEdge AND NOT openLimit THEN
                state := 1;
                errorFlag := FALSE;
            ELSIF closeEdge AND NOT closeLimit THEN
                state := 2;
                errorFlag := FALSE;
            END_IF
        1:
            IF openLimit THEN
                state := 0;
            END_IF
        2:
            IF closeLimit THEN
                state := 0;
            END_IF
        3:
            (* 故障锁存：按第 8 条，只有两键同按才算人工复位。
               障碍消失只是"可以复位了"，不是"已经复位"——
               否则障碍消失的那一拍就会允许起机，违反第 7 条。 *)
            IF openBtn AND closeBtn THEN
                state := 0;
                errorFlag := FALSE;
            END_IF
    END_CASE

    (* 电机输出由状态唯一决定，互锁保证不会同时两个方向 *)
    motorUp := (state = 1);
    motorDown := (state = 2);
END_IF
END_FUNCTION_BLOCK
