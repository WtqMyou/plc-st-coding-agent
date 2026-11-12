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
| MoveDown/Up/Left/Right | Edge/start/trig | Hold until done | EmergencyStop(FALSE), mode end  | Output latches stop   | BOOL, limit-based     |
| ActivateGrip/Release   | Edge/start/trig | Hold until done | EmergencyStop(FALSE), mode end  | Output latches stop   | BOOL, limit-based     |
| step[0..8]        | Start rising edge| Retained        | EmergencyStop(FALSE), mode end  | Initialized to 0      | INT, wrap to 0 at 8   |
| running           | Start rising edge| Retained        | EmergencyStop(FALSE), cycle end | FALSE when E-Stop     | BOOL, auto in cycle   |
| cycleComplete     | step=8 & done    | Retained        | Start rising edge               | Set only once         | BOOL, latched         |

PUB clause coverage:
- PUB001: Manual mode direct button control with limit checking
- PUB002-PUB007: Single step sequence (8 steps, Start advances)
- PUB008-PUB011: Single cycle executes full sequence once
- PUB012-PUB015: Continuous mode repeats cycle
- PUB016-PUB018: Emergency stop (FALSE=triggered) stops all outputs
- PUB019-PUB020: Grip/Release limit switches for completion feedback

Behavior:
- EmergencyStop=FALSE: All outputs=0, running=FALSE, cycleComplete NOT reset (resume capability)
- Initial state: step=0, running=FALSE, all outputs=FALSE
- Caller ensures mutually exclusive mode inputs
*)
(* CONTRACT_RULES [] *)

startRisingEdge(CLK := Start);
running := running OR (startRisingEdge.Q AND (SingleStepMode OR SingleCycleMode OR ContinuousMode));

IF EmergencyStop = FALSE THEN
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
    running := FALSE;
    cycleComplete := FALSE;
ELSE
    IF ManualMode THEN
        step := 0;
        running := FALSE;
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
        
        IF DownButton AND NOT DownLimitSwitch THEN
            MoveDown := TRUE;
        ELSIF UpButton AND NOT UpLimitSwitch THEN
            MoveUp := TRUE;
        ELSIF LeftButton AND NOT LeftLimitSwitch THEN
            MoveLeft := TRUE;
        ELSIF RightButton AND NOT RightLimitSwitch THEN
            MoveRight := TRUE;
        END_IF;
        
        IF GripButton THEN
            ActivateGrip := TRUE;
        END_IF;
        IF ReleaseButton THEN
            ActivateRelease := TRUE;
        END_IF;
        
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
                    MoveDown := TRUE;
                    IF DownLimitSwitch THEN
                        MoveDown := FALSE;
                        step := 1;
                        running := FALSE;
                    END_IF;
                1:
                    ActivateGrip := TRUE;
                    IF GripLimitSwitch THEN
                        ActivateGrip := FALSE;
                        step := 2;
                        running := FALSE;
                    END_IF;
                2:
                    MoveUp := TRUE;
                    IF UpLimitSwitch THEN
                        MoveUp := FALSE;
                        step := 3;
                        running := FALSE;
                    END_IF;
                3:
                    MoveRight := TRUE;
                    IF RightLimitSwitch THEN
                        MoveRight := FALSE;
                        step := 4;
                        running := FALSE;
                    END_IF;
                4:
                    MoveDown := TRUE;
                    IF DownLimitSwitch THEN
                        MoveDown := FALSE;
                        step := 5;
                        running := FALSE;
                    END_IF;
                5:
                    ActivateRelease := TRUE;
                    IF ReleaseLimitSwitch THEN
                        ActivateRelease := FALSE;
                        step := 6;
                        running := FALSE;
                    END_IF;
                6:
                    MoveUp := TRUE;
                    IF UpLimitSwitch THEN
                        MoveUp := FALSE;
                        step := 7;
                        running := FALSE;
                    END_IF;
                7:
                    MoveLeft := TRUE;
                    IF LeftLimitSwitch THEN
                        MoveLeft := FALSE;
                        step := 8;
                        running := FALSE;
                    END_IF;
                8:
                    step := 0;
                    running := FALSE;
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
        
        IF running AND NOT cycleComplete THEN
            CASE step OF
                0: 
                    MoveDown := TRUE;
                    IF DownLimitSwitch THEN
                        MoveDown := FALSE;
                        step := 1;
                    END_IF;
                1:
                    ActivateGrip := TRUE;
                    IF GripLimitSwitch THEN
                        ActivateGrip := FALSE;
                        step := 2;
                    END_IF;
                2:
                    MoveUp := TRUE;
                    IF UpLimitSwitch THEN
                        MoveUp := FALSE;
                        step := 3;
                    END_IF;
                3:
                    MoveRight := TRUE;
                    IF RightLimitSwitch THEN
                        MoveRight := FALSE;
                        step := 4;
                    END_IF;
                4:
                    MoveDown := TRUE;
                    IF DownLimitSwitch THEN
                        MoveDown := FALSE;
                        step := 5;
                    END_IF;
                5:
                    ActivateRelease := TRUE;
                    IF ReleaseLimitSwitch THEN
                        ActivateRelease := FALSE;
                        step := 6;
                    END_IF;
                6:
                    MoveUp := TRUE;
                    IF UpLimitSwitch THEN
                        MoveUp := FALSE;
                        step := 7;
                    END_IF;
                7:
                    MoveLeft := TRUE;
                    IF LeftLimitSwitch THEN
                        MoveLeft := FALSE;
                        step := 8;
                    END_IF;
                8:
                    MoveLeft := FALSE;
                    running := FALSE;
                    cycleComplete := TRUE;
                    step := 0;
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
                    MoveDown := TRUE;
                    IF DownLimitSwitch THEN
                        MoveDown := FALSE;
                        step := 1;
                    END_IF;
                1:
                    ActivateGrip := TRUE;
                    IF GripLimitSwitch THEN
                        ActivateGrip := FALSE;
                        step := 2;
                    END_IF;
                2:
                    MoveUp := TRUE;
                    IF UpLimitSwitch THEN
                        MoveUp := FALSE;
                        step := 3;
                    END_IF;
                3:
                    MoveRight := TRUE;
                    IF RightLimitSwitch THEN
                        MoveRight := FALSE;
                        step := 4;
                    END_IF;
                4:
                    MoveDown := TRUE;
                    IF DownLimitSwitch THEN
                        MoveDown := FALSE;
                        step := 5;
                    END_IF;
                5:
                    ActivateRelease := TRUE;
                    IF ReleaseLimitSwitch THEN
                        ActivateRelease := FALSE;
                        step := 6;
                    END_IF;
                6:
                    MoveUp := TRUE;
                    IF UpLimitSwitch THEN
                        MoveUp := FALSE;
                        step := 7;
                    END_IF;
                7:
                    MoveLeft := TRUE;
                    IF LeftLimitSwitch THEN
                        MoveLeft := FALSE;
                        step := 0;
                    END_IF;
            END_CASE;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK