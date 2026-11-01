FUNCTION_BLOCK FB
VAR_INPUT
    pushEn : BOOL;
    pushItem : INT;
    popEn : BOOL;
END_VAR
(* fifo 由调用方分配、FB 内部读写，必须是 VAR_IN_OUT；写成 VAR_INPUT 就成了
   只读形参，往里面写会被静态检查直接拒掉（E_WRITE_INPUT）。 *)
VAR_IN_OUT
    fifo : ARRAY[1..8] OF INT;
END_VAR
VAR_OUTPUT
    count : INT;
    full : BOOL;
    empty : BOOL;
    head : INT;
END_VAR
VAR
    pushPrev : BOOL;
    popPrev : BOOL;
    pushEdge : BOOL;
    popEdge : BOOL;
    wr : INT := 1;
    rd : INT := 1;
END_VAR

(* 边沿 = 本周期电平 且 上次周期不是这个电平。
   把"上次电平"和"本周期边沿"分两个变量存，别把边沿算回同一个变量：
   pushEdge := pushEn AND NOT pushEdge 这种写法把边沿覆盖掉上次电平，
   一旦电平连续两个周期为真（如 q7 同周期出队+入队），第二周期算不出边沿，
   入队被静默丢弃。 *)
pushEdge := pushEn AND NOT pushPrev;
popEdge := popEn AND NOT popPrev;
pushPrev := pushEn;
popPrev := popEn;

(* 出队：空队列忽略。先把"这一笔算数"的判断用局部变量兜住，
   因为下面 count := count - 1 已经改变了判断依据。 *)
IF popEdge AND count > 0 THEN
    count := count - 1;
    rd := rd + 1;
    IF rd > 8 THEN
        rd := 1;
    END_IF
END_IF

(* 入队：满队列丢弃。入队判定用**出队之后**的 count，
   所以同一周期既有出队又有入队时，这一格是真的能腾出来用的。 *)
IF pushEdge AND count < 8 THEN
    fifo[wr] := pushItem;
    count := count + 1;
    wr := wr + 1;
    IF wr > 8 THEN
        wr := 1;
    END_IF
END_IF

(* 队列空了指针才归位。必须放在出入队之后，而且要精确到"本周期结束时
   真正空了"；写在这个位置、用 count = 0 判定即可：上面的入队已经执行完，
   同一周期出队腾空又入队时 count 不会是 0，不会被误清零。 *)
IF count <= 0 THEN
    rd := 1;
    wr := 1;
END_IF

full := count >= 8;
empty := count <= 0;
IF empty THEN
    head := 0;
ELSE
    head := fifo[rd];
END_IF
END_FUNCTION_BLOCK
