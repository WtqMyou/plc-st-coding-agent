(*
  FIFO Circular Queue with VARIANT Storage — 参考解（public-hard-04）

  容量与元素类型都来自调用方数组 buffer（VARIANT 里的真实数组，容量 = 数组长度），
  内部只维护 head（队头下标，1 起）与 count（有效元素个数）；tail 由二者算出，
  head/tail/count 都不出现在接口上（R6）。

  需求编号：
    R1  入队请求上升沿 -> 队列未满时把当前 item 追加到队尾
    R2  出队请求上升沿 -> 队列非空时移除队首并把该值写回 item
    R3  reset=TRUE 清空队列、elementCount=0，且优先于入队/出队
    R4  elementCount 输出当前有效元素个数（0 空、等于容量为满）
    R5  空队出队/满队入队要拒绝：队列与 item 保持不变，status 说明原因
    R6  首次调用时队列为空；head/tail 等内部状态不出现在接口上
*)

FUNCTION_BLOCK FB
VAR_INPUT
  enqueue : BOOL;                (* R1 入队请求，一个上升沿执行一次 *)
  dequeue : BOOL;                (* R2 出队请求，一个上升沿执行一次 *)
  reset : BOOL;                  (* R3 复位，优先于入队/出队 *)
END_VAR
VAR_OUTPUT
  elementCount : DINT;           (* R4 当前有效元素个数 *)
  status : WORD;                 (* R5 16#0000 / 16#8001 / 16#8002 *)
END_VAR
VAR_IN_OUT
  item : VARIANT;                (* 入队时读取；出队成功时写回被移除的队首值 *)
  buffer : VARIANT;              (* 队列存储，容量 = 数组实际长度 *)
END_VAR
VAR
  cap : DINT;                    (* 本拍看到的容量 *)
  count : DINT;                  (* 有效元素个数，不放接口（R6） *)
  head : DINT;                   (* 队头下标（1 起） *)
  tail : DINT;                   (* 队尾插入位置（由 head+count 算出） *)
  enEdge : BOOL;  enPrev : BOOL; (* R1 上升沿 *)
  deEdge : BOOL;  dePrev : BOOL; (* R2 上升沿 *)
END_VAR

(* 容量每拍从调用方数组重新取：数组换长度时行为随之改变 *)
cap := UPPER_BOUND(buffer, 1) - LOWER_BOUND(buffer, 1) + 1;

(* 内部下标兜底：首次调用 / 复位后 head 一定落在 1..cap *)
IF count < 0 THEN
  count := 0;
END_IF
IF head < 1 THEN
  head := 1;
END_IF

(* 上升沿：一次请求只执行一次，按住不放不会重复入队/出队 *)
enEdge := enqueue AND NOT enPrev;
enPrev := enqueue;
deEdge := dequeue AND NOT dePrev;
dePrev := dequeue;

(* 状态码是"拍"语义：每拍先回到 16#0000，只有被拒绝的那一拍才置错误码 *)
status := 16#0000;

IF reset THEN
  (* R3 复位优先：同时到来的入队/出队请求被丢弃，只清空队列 *)
  count := 0;
  head := 1;
ELSIF enEdge THEN
  (* R1 入队 *)
  IF (cap <= 0) OR (count >= cap) THEN
    status := 16#8002;         (* R5 满队（容量为 0 的数组也按"装不下"拒绝） *)
  ELSE
    IF count > cap - head THEN
      tail := count - (cap - head);
    ELSE
      tail := head + count;    (* 此分支已知和不超过 cap，适用于 DINT 极值容量 *)
    END_IF
    buffer[LOWER_BOUND(buffer, 1) + (tail - 1)] := item;      (* VARIANT 元素写入：类型由数组元素决定 *)
    count := count + 1;
  END_IF
ELSIF deEdge THEN
  (* R2 出队 *)
  IF count <= 0 THEN
    status := 16#8001;         (* R5 空队，item 保持原值 *)
  ELSE
    item := buffer[LOWER_BOUND(buffer, 1) + (head - 1)];      (* 被移除的队首值写回 item *)
    IF head = cap THEN
      head := 1;
    ELSE
      head := head + 1;
    END_IF
    count := count - 1;
  END_IF
END_IF

(* R4 *)
elementCount := count;

END_FUNCTION_BLOCK
