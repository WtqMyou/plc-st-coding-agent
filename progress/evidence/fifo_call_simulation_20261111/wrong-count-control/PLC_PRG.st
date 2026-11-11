(* Simulation-only test program; call once per task scan from a fresh instance. *)
PROGRAM PLC_PRG
VAR
    q2 : FB;
    q4 : FB;
    item2 : DINT;
    item4 : DINT;
    storage2 : ARRAY[-2..-1] OF DINT;
    storage4 : ARRAY[7..10] OF DINT;
    step : INT;
    en : BOOL;
    de : BOOL;
    rst : BOOL;
    ok : BOOL;
    failed : BOOL;
    firstFailedStep : INT := -1;
    testComplete : BOOL;
    testPassed : BOOL;
END_VAR

IF NOT testComplete THEN
    en := FALSE;
    de := FALSE;
    rst := FALSE;
    CASE step OF
        0: rst := TRUE;
        1: en := TRUE; item2 := 10; item4 := 10;
        3: en := TRUE; item2 := 20; item4 := 20;
        5: en := TRUE; item2 := 30; item4 := 30;
        6: de := TRUE;
        7: en := TRUE; item2 := 40; item4 := 40;
        8: de := TRUE;
        10: de := TRUE;
        12: de := TRUE;
    END_CASE;

    q2(enqueue := en, dequeue := de, reset := rst, item := item2, buffer := storage2);
    q4(enqueue := en, dequeue := de, reset := rst, item := item4, buffer := storage4);
    ok := (q2.status = 16#0000) AND (q4.status = 16#0000);
    CASE step OF
        0: ok := ok AND (q2.elementCount = 0) AND (q4.elementCount = 0);
        1, 2: ok := ok AND (q2.elementCount = 1) AND (q4.elementCount = 1);
        3, 4: ok := ok AND (q2.elementCount = 2) AND (q4.elementCount = 2);
        5: ok := (q2.status = 16#8002) AND (q4.status = 16#0000)
                 AND (q2.elementCount = 2) AND (q4.elementCount = 3);
        6: ok := ok AND (item2 = 10) AND (item4 = 10)
                    AND (q2.elementCount = 1) AND (q4.elementCount = 2);
        7: ok := ok AND (q2.elementCount = 2) AND (q4.elementCount = 3);
        8, 9: ok := ok AND (item2 = 20) AND (item4 = 20)
                       AND (q2.elementCount = 1) AND (q4.elementCount = 2);
        10, 11: ok := ok AND (item2 = 40) AND (item4 = 30)
                         AND (q2.elementCount = 0) AND (q4.elementCount = 1);
        12: ok := (q2.status = 16#8001) AND (q4.status = 16#0000)
                  AND (item2 = 40) AND (item4 = 40)
                  AND (q2.elementCount = 0) AND (q4.elementCount = 0);
        13: ok := ok AND (q2.elementCount = 0) AND (q4.elementCount = 0);
    END_CASE;
    IF NOT ok AND NOT failed THEN
        failed := TRUE;
        firstFailedStep := step;
    END_IF;
    IF step = 13 THEN
        testComplete := TRUE;
        testPassed := NOT failed;
    ELSE
        step := step + 1;
    END_IF;
END_IF;
END_PROGRAM
