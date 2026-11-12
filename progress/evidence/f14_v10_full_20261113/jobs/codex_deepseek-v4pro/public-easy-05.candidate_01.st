FUNCTION_BLOCK WeldGapAlarmFB
VAR_INPUT
    Gap_Exceeded        : BOOL;
    Weld_E_Stop_NC      : BOOL;
    DebounceTime        : TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert       : BOOL;
    Weld_Soft_Start_Active : BOOL;
END_VAR
VAR
    InitTimer       : TON;
    DebounceTimer   : TON;
    InitComplete    : BOOL;
    NormalMonitor   : BOOL;
END_VAR

(*
ENGINEERING_CONTRACT
- Operator_Alert: activates only when initialization is complete, E-stop is inactive,
  and Gap_Exceeded has remained TRUE for DebounceTime (PUB003, PUB004).
  It is FALSE during the 5 s initialization period (PUB002).
- Operator_Alert reset: immediately FALSE when Gap_Exceeded becomes FALSE or E-stop
  becomes active; normal-monitoring conditions must remain true to hold it (PUB003, PUB004).
- Debounce timing: accumulates only during initialized normal monitoring with E-stop
  inactive and resets when Gap_Exceeded is FALSE or E-stop is active (PUB002, PUB003, PUB004).
- Weld_Soft_Start_Active: TRUE only during the first 5 s after power-up, independent of
  E-stop state; it is not a speed ramp (PUB002, PUB005). E-stop state is not specified
  for this output.
- Boundaries/units: initialization is fixed T#5S; DebounceTime uses TIME milliseconds.
  TON activation occurs at elapsed time >= PT.
*)

InitTimer(IN := TRUE, PT := T#5S);
InitComplete := InitTimer.Q;
NormalMonitor := InitComplete AND Weld_E_Stop_NC;

DebounceTimer(IN := Gap_Exceeded AND NormalMonitor, PT := DebounceTime);

Operator_Alert := NormalMonitor AND DebounceTimer.Q;
Weld_Soft_Start_Active := NOT InitComplete;

(* CONTRACT_RULES [] *)
END_FUNCTION_BLOCK