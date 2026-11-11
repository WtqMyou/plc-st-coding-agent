FUNCTION_BLOCK FB
VAR_INPUT
    pushEn  : BOOL;          // 入队指令（上升沿有效）
    pushItem: INT;           // 入队物料号
    popEn   : BOOL;          // 出队指令（上升沿有效）
END_VAR
VAR_INOUT
    fifo : ARRAY[1..8] OF INT; // 队列缓冲区，下标 1 为最老元素
END_VAR
VAR_OUTPUT
    count : INT;             // 当前队列元素个数 0..8
    full  : BOOL;            // 队列满
    empty : BOOL;            // 队列空
    head  : INT;             // 队首元素（空时保持 0）
END_VAR
VAR
    prevPush : BOOL := FALSE; // 上一周期 pushEn 的状态
    prevPop  : BOOL := FALSE; // 上一周期 popEn 的状态
    i        : INT;          // 循环计数器
END_VAR

    // ------------------------------------------------------------
    // 1. 出队：popEn 上升沿先执行（仅在队列非空时有效）
    // ------------------------------------------------------------
    IF popEn AND NOT prevPop THEN
        IF count > 0 THEN
            // 将所有有效元素左移一位，实现移除 fifo[1]
            FOR i := 1 TO count - 1 DO
                fifo[i] := fifo[i + 1];
            END_FOR
            // 将被腾出的最后一个位置清零（可选，满足“紧凑”要求）
            fifo[count] := 0;
            count := count - 1;
        END_IF
    END_IF

    // ------------------------------------------------------------
    // 2. 入队：pushEn 上升沿随后执行（仅在队列未满时有效）
    // ------------------------------------------------------------
    IF pushEn AND NOT prevPush THEN
        IF count < 8 THEN
            count := count + 1;
            fifo[count] := pushItem;   // 新元素追加到逻辑队尾
        END_IF
    END_IF

    // ------------------------------------------------------------
    // 3. 输出信号
    // ------------------------------------------------------------
    full  := (count = 8);
    empty := (count = 0);
    head  := 0;
    IF NOT empty THEN
        head := fifo[1];
    END_IF

    // ------------------------------------------------------------
    // 4. 更新历史状态，供下一周期边沿检测使用
    // ------------------------------------------------------------
    prevPush := pushEn;
    prevPop  := popEn;
END_FUNCTION_BLOCK