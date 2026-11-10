(* 结构体必须显式定义：题目给的是 IN_OUT ARRAY[1..5] OF ST_Pump，
   没有 TYPE 块就读不到字段名，pumpGroup[i].xxx 会被判错。 *)
TYPE ST_Pump :
STRUCT
    priority : INT;    (* 优先级，越大越优先；本 FB 只读 *)
    selection : BOOL;  (* 手动选中状态；本 FB 只读 *)
    RunComd : BOOL;    (* 本 FB 唯一写的字段 *)
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_MultiPump
VAR_INPUT
    mode : BOOL;   (* FALSE: 手动；TRUE: 自动 *)
    start : BOOL;  (* 启动按钮 *)
    stop : BOOL;   (* 停止按钮：停全部泵 *)
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    i : INT;
    j : INT;
    rank : INT;      (* 第 i 台泵在 5 台里的优先级名次（0 最高） *)
    prioI : INT;
    prioJ : INT;
    inTop3 : BOOL;
END_VAR

(* R4: 停止按钮优先于一切——先无条件把 5 台泵的命令都置 FALSE，
   再进入模式分支；这样 stop 与 start 同时按下时表现为停止。 *)
IF stop THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR

(* R1: 依据 mode 切换运行方式。 *)
ELSIF mode THEN
    (* R3: 自动方式——按 priority 选 3 台（三用两备）。
       不排序、不搬结构体：名次 = 优先级比我高（或同级但下标更小）的台数，
       名次 < 3 即为前三。优先级相同按下标小者优先，保证结果唯一。 *)
    FOR i := 1 TO 5 DO
        rank := 0;
        prioI := pumpGroup[i].priority;
        FOR j := 1 TO 5 DO
            IF j <> i THEN
                prioJ := pumpGroup[j].priority;
                IF (prioJ > prioI) OR ((prioJ = prioI) AND (j < i)) THEN
                    rank := rank + 1;
                END_IF
            END_IF
        END_FOR
        inTop3 := rank < 3;
        (* R2': 自动方式下 start 启动被选中的前 3 台，备用的 2 台必须停机命令 *)
        pumpGroup[i].RunComd := start AND inTop3;
    END_FOR

ELSE
    (* R2: 手动方式——按 selection 逐台控制：选中的泵由 start 启动，
       未选中的泵给停机命令（互斥，不允许两台互相抢）。 *)
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := start AND pumpGroup[i].selection;
    END_FOR
END_IF

END_FUNCTION_BLOCK
