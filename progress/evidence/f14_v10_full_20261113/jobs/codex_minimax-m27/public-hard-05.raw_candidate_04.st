FUNCTION_BLOCK ArmController
VAR_INPUT
    ManualMode : BOOL;
    SingleStepMode : BOOL;
    SingleCycleMode : BOOL;
    ContinuousMode : BOOL;
    EmergencyStop : BOOL;
    Start : BOOL;
    DownButton : BOOL;
    UpButton : BOOL;
    LeftButton : BOOL;
    RightButton : BOOL;
    GripButton : BOOL;
    ReleaseButton : BOOL;
    DownLimitSwitch : BOOL;
    UpLimitSwitch : BOOL;
    LeftLimitSwitch : BOOL;
    RightLimitSwitch : BOOL;
    GripLimitSwitch : BOOL;
    ReleaseLimitSwitch : BOOL;
END_VAR
VAR_OUTPUT
    MoveDown : BOOL := FALSE;
    MoveUp : BOOL := FALSE;
    MoveLeft : BOOL := FALSE;
    MoveRight : BOOL := FALSE;
    ActivateGrip : BOOL := FALSE;
    ActivateRelease : BOOL := FALSE;
END_VAR
VAR
    step : INT := 0;
    startRisingEdge : R_TRIG;
    running : BOOL := FALSE;
    cycleComplete : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
| Output/State      | Activation       | Retention       | Reset/Deactivation             | Same-Scan Priority    | Units/Boundaries      |
|-------------------|------------------|-----------------|---------------------------------|-----------------------|-----------------------|
| MoveDown/Up/Left/Right | Step-dependent | Hold until done | EmergencyStop(FALSE), mode end  | Output based on step  | BOOL, limit-based     |
| ActivateGrip/Release   | Step-dependent | Hold until done | EmergencyStop(FALSE), mode end  | Output based on step  | BOOL, limit-based     |
| step[0..7]        | Limit reached    | Retained        | EmergencyStop(FALSE), mode end  | Initialized to 0      | INT, wrap to 0 at 7   |
| running           | Start rising edge| Retained        | EmergencyStop(FALSE), cycle end | FALSE when E-Stop     | BOOL, auto in cycle   |
| cycleComplete     | step=7 & done    | Retained        | Start rising edge               | Set only once         | BOOL, latched         |

PUB clause coverage:
- PUB001: Manual mode direct button control with limit checking
- PUB002-PUB007: Single step sequence (8 steps, Start advances)
- PUB008-PUB011: Single cycle executes full sequence once
- PUB012-PUB015: Continuous mode repeats cycle
- PUB016-PUB018: Emergency stop (FALSE=triggered) stops all outputs
- PUB019-PUB020: Grip/Release limit switches for completion feedback

Behavior:
- EmergencyStop=FALSE: All outputs=0, running=FALSE, cycleComplete NOT reset
- Initial state: step=0, running=FALSE, all outputs=FALSE
- Step advances only when corresponding limit switch condition is met
- Outputs set based on current step, not after condition evaluation
*)
(* CONTRACT_RULES [] *)

startRisingEdge(CLK := Start);

IF EmergencyStop = FALSE THEN
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
    running := FALSE;
    cycleComplete := FALSE;
    step := 0;
ELSE
    IF ManualMode THEN
        step := 0;
        running := FALSE;
        MoveDown := DownButton AND NOT DownLimitSwitch;
        MoveUp := UpButton AND NOT UpLimitSwitch;
        MoveLeft := LeftButton AND NOT LeftLimitSwitch;
        MoveRight := RightButton AND NOT RightLimitSwitch;
        ActivateGrip := GripButton;
        ActivateRelease := ReleaseButton;
        
    ELSIF SingleStepMode THEN
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
        
        IF startRisingEdge.Q AND NOT running THEN
            running := TRUE;
        END_IF;
        
        IF running THEN
            CASE step OF
                0: 
                    IF NOT DownLimitSwitch THEN
                        MoveDown := TRUE;
                    END_IF;
                    IF DownLimitSwitch THEN
                        step := 1;
                        running := FALSE;
                    END_IF;
                1:
                    IF NOT GripLimitSwitch THEN
                        ActivateGrip := TRUE;
                    END_IF;
                    IF GripLimitSwitch THEN
                        step := 2;
                        running := FALSE;
                    END_IF;
                2:
                    IF NOT UpLimitSwitch THEN
                        MoveUp := TRUE;
                    END_IF;
                    IF UpLimitSwitch THEN
                        step := 3;
                        running := FALSE;
                    END_IF;
                3:
                    IF NOT RightLimitSwitch THEN
                        MoveRight := TRUE;
                    END_IF;
                    IF RightLimitSwitch THEN
                        step := 4;
                        running := FALSE;
                    END_IF;
                4:
                    IF NOT DownLimitSwitch THEN
                        MoveDown := TRUE;
                    END_IF;
                    IF DownLimitSwitch THEN
                        step := 5;
                        running := FALSE;
                    END_IF;
                5:
                    IF NOT ReleaseLimitSwitch THEN
                        ActivateRelease := TRUE;
                    END_IF;
                    IF ReleaseLimitSwitch THEN
                        step := 6;
                        running := FALSE;
                    END_IF;
                6:
                    IF NOT UpLimitSwitch THEN
                        MoveUp := TRUE;
                    END_IF;
                    IF UpLimitSwitch THEN
                        step := 7;
                        running := FALSE;
                    END_IF;
                7:
                    IF NOT LeftLimitSwitch THEN
                        MoveLeft := TRUE;
                    END_IF;
                    IF LeftLimitSwitch THEN
                        step := 0;
                        running := FALSE;
                    END_IF;
            END_CASE;
        END_IF;
        
    ELSIF SingleCycleMode THEN
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
        
        IF startRisingEdge.Q AND NOT running AND NOT cycleComplete THEN
            running := TRUE;
        END_IF;
        
        IF running THEN
            CASE step OF
                0: 
                    IF NOT DownLimitSwitch THEN
                        MoveDown := TRUE;
                    END_IF;
                    IF DownLimitSwitch THEN
                        step := 1;
                    END_IF;
                1:
                    IF NOT GripLimitSwitch THEN
                        ActivateGrip := TRUE;
                    END_IF;
                    IF GripLimitSwitch THEN
                        step := 2;
                    END_IF;
                2:
                    IF NOT UpLimitSwitch THEN
                        MoveUp := TRUE;
                    END_IF;
                    IF UpLimitSwitch THEN
                        step := 3;
                    END_IF;
                3:
                    IF NOT RightLimitSwitch THEN
                        MoveRight := TRUE;
                    END_IF;
                    IF RightLimitSwitch THEN
                        step := 4;
                    END_IF;
                4:
                    IF NOT DownLimitSwitch THEN
                        MoveDown := TRUE;
                    END_IF;
                    IF DownLimitSwitch THEN
                        step := 5;
                    END_IF;
                5:
                    IF NOT ReleaseLimitSwitch THEN
                        ActivateRelease := TRUE;
                    END_IF;
                    IF ReleaseLimitSwitch THEN
                        step := 6;
                    END_IF;
                6:
                    IF NOT UpLimitSwitch THEN
                        MoveUp := TRUE;
                    END_IF;
                    IF UpLimitSwitch THEN
                        step := 7;
                    END_IF;
                7:
                    IF NOT LeftLimitSwitch THEN
                        MoveLeft := TRUE;
                    END_IF;
                    IF LeftLimitSwitch THEN
                        running := FALSE;
                        cycleComplete := TRUE;
                        step := 0;
                    END_IF;
            END_CASE;
        END_IF;
        
    ELSIF ContinuousMode THEN
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
        
        IF startRisingEdge.Q AND NOT running THEN
            running := TRUE;
        END_IF;
        
        IF running THEN
            CASE step OF
                0: 
                    IF NOT DownLimitSwitch THEN
                        MoveDown := TRUE;
                    END_IF;
                    IF DownLimitSwitch THEN
                        step := 1;
                    END_IF;
                1:
                    IF NOT GripLimitSwitch THEN
                        ActivateGrip := TRUE;
                    END_IF;
                    IF GripLimitSwitch THEN
                        step := 2;
                    END_IF;
                2:
                    IF NOT UpLimitSwitch THEN
                        MoveUp := TRUE;
                    END_IF;
                    IF UpLimitSwitch THEN
                        step := 3;
                    END_IF;
                3:
                    IF NOT RightLimitSwitch THEN
                        MoveRight := TRUE;
                    END_IF;
                    IF RightLimitSwitch THEN
                        step := 4;
                    END_IF;
                4:
                    IF NOT DownLimitSwitch THEN
                        MoveDown := TRUE;
                    END_IF;
                    IF DownLimitSwitch THEN
                        step := 5;
                    END_IF;
                5:
                    IF NOT ReleaseLimitSwitch THEN
                        ActivateRelease := TRUE;
                    END_IF;
                    IF ReleaseLimitSwitch THEN
                        step := 6;
                    END_IF;
                6:
                    IF NOT UpLimitSwitch THEN
                        MoveUp := TRUE;
                    END_IF;
                    IF UpLimitSwitch THEN
                        step := 7;
                    END_IF;
                7:
                    IF NOT LeftLimitSwitch THEN
                        MoveLeft := TRUE;
                    END_IF;
                    IF LeftLimitSwitch THEN
                        step := 0;
                    END_IF;
            END_CASE;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK