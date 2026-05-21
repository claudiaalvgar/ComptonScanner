# Compton Scanner — TMCM-3351 Motor Controller Scripts

Hardware: TMCM-3351 3-axis closed-loop stepper motor controller.
Three sleds move vertically. Positive encoder direction = downward, negative = upward.

---

## Main script: FullTest_CreatorMode.tmc

Single self-contained TMCL script with all routines. Open in TMCL-IDE Creator Mode,
uncomment the steps you want to run, and execute.

### Routine execution order

**Step 1 — always run first at startup**
```
CSUB PowerOn
CSUB StartInit
CSUB DisableClosedLoop
CSUB EnableClosedLoop
CSUB ReferenceZero
```
Sets motion parameters, PID/regulator values, enables closed loop, and sets the
current sled positions as coordinate origin (encoder = 0).

**Step 2 — calibrate to copper block (one axis at a time)**

Uncomment only the axis block you want to calibrate in `StartCalibration2`.
Each axis has to be done independently — user variables in bank 2 persist per axis.
Make sure all 3 axes have been calibrated before running StartMove2.

**Step 3 — move upward and hard stop**
```
CSUB StartMove2
```
Moves all axes 500,000 encoder counts above their saved copper block positions.
To change the target height, modify the `CALC SUB,500000` value in `StartMove2`.
The same routine can be re-run with a different offset to move up or down from
the current position.

**Step 4 — power off**
```
CSUB PowerOff
```

---

### What MST does and why it matters

`MST x` issues an immediate motor stop command. In closed-loop mode, after the motor
stalls against the copper block, the CL controller has been fighting at maximum current
with its integrator wound up. `MST` stops the commanded motion but does NOT reset the
chip internal state (commutation angle tracking, integrator).

### Why ReferenceZero works at startup but not after calibration

`ReferenceZero` resets encoder position (SAP 209 = 0), then syncs actual position
(AAP 1) and target position (AAP 0) to match. At startup this is safe: the CL
controller is in a clean state, no prior stall, all registers are consistent.

After copper block calibration, the internal state has diverged from
what a clean power-on provides. Calling `ReferenceZero` at this point resets the
TMCL-visible registers (SAP 209, AAP 1, AAP 0) but NOT the chip's internal state.
The CL controller then has a mismatch between its internal commutation state and
the new encoder=0 reference, which causes it to behave incorrectly during StartMove.

Re-running the full init sequence (PowerOn → StartInit → DisableCL → EnableCL →
ReferenceZero) after calibration does NOT fix this: PowerOn already contains the
same position sync as ReferenceZero, so the same corruption occurs.

### The fix: save encoder positions, never reset reference after calibration

`StartCalibration2` saves `GAP 209` (encoder position) for each axis at the moment
the sled stalls on the copper block, storing it in user variable bank 2 (indices 0/1/2).
`StartMove2` reads these saved positions and computes absolute targets
(`copper_block_pos - 500000`) via `GGP / CALC SUB / ACO`, then calls `MVP COORD`.

This means:
- No `ReferenceZero` is ever called after calibration
- The CL controller's internal state is undisturbed from when the motor stopped
- Hard stop detection works correctly

### User variable map (bank 2, accessed via AGP/GGP)

| Index | Name            | Contents                                  |
|-------|-----------------|-------------------------------------------|
| 0     | CALIB_POS_AXIS0 | Encoder position at copper block, axis 0  |
| 1     | CALIB_POS_AXIS1 | Encoder position at copper block, axis 1  |
| 2     | CALIB_POS_AXIS2 | Encoder position at copper block, axis 2  |

User variables persist as long as the board is powered. Calibrating one axis does
not overwrite the others.

---

## Approach A (deprecated): StartCalibration + StartMove

`StartCalibration` moves each axis to the copper block and stops. After this, the
only valid next step is `StartMove` immediately — no `ReferenceZero`, no
`DisableCL/EnableCL` in between. `StartMove` uses hardcoded target `SCO 0,x,-500000`,
which is only meaningful if `ReferenceZero` was called at startup (so -500,000 is
500,000 counts above origin, not above the copper block).

If `ReferenceZero` or `DisableCL/EnableCL` is called after `StartCalibration`,
hard stop detection breaks. Recovery requires a full board power-cycle and rerunning
Step 1 from scratch.

This approach is kept in the script for reference but `StartCalibration2 + StartMove2`
should be used instead.


---

## Other scripts (legacy, single-step use)

| Script                              | Purpose                                      |
|-------------------------------------|----------------------------------------------|
| 1step_CreatorMode_3axisMove.tmc     | Set up closed loop and initial variables     |
| 2step_actualspeed_CreatorMode_3axisMove.tmc | Speed monitoring variant               |
| CalibrationMode_HitPlatform.tmc     | Calibrate by hitting bottom platform         |
| CalibrationMode_MetalBlock.tmc      | Calibrate by hitting metal block             |
| TMCM_FullCreatorMode.tmc            | Awaiting Julia inputs (not tested)           |

# Script meant to be looping in the tmcm board waiting for julia inputs (not tested yet):

TMCMCode_newversion.tmc