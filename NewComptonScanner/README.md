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

**Step 2 — calibrate to calibration blocks**

Two options are available:

*Option A — one axis at a time (`StartCalibration2`):*
Uncomment only the axis block you want to calibrate. Each axis must be done
independently — user variables in bank 2 persist per axis. Make sure all 3 axes
have been calibrated before running StartMove2.

*Option B — all 3 axes simultaneously (`StartCalibrationSimultaneousAxis`):*
```
CSUB StartCalibrationSimultaneousAxis
```
Starts all 3 axes at once, polls them in a round-robin loop, and saves each
axis's encoder position the instant it stalls against its block. MST is issued
per axis immediately on stall — no axis is held against its block waiting for
the others. Use this option when all 3 blocks are in position and the sleds
start physically above the blocks.

**Step 3 — move upward and hard stop**
```
CSUB StartMove2
```
Moves all axes 500,000 encoder counts above their saved copper block positions.
To change the target height, modify the `CALC SUB,500000` value in `StartMove2`.
The same routine can be re-run with a different offset to move up or down from
the current position.

**Step 4 — measurement mode (optional)**
```
CSUB EnterMeasurementMode
// perform HPGe measurement
CSUB ExitMeasurementMode
```
`EnterMeasurementMode` de-energizes motors for low-noise HPGe detector data acquisition:
1. Stops all axes (`MST 0/1/2`) and polls `GAP 3` until each axis confirms stopped.
2. Waits 50 ticks for mechanical settling.
3. Syncs target position (`AAP 0`) to current encoder (`GAP 209`) — prevents the CL
   controller from fighting to return to an old move target when current is restored.
4. Sets `SAP 6` (run current) and `SAP 7` (hold current) to 0, stopping all PWM
   switching and eliminating motor EMI during measurement.
5. Waits 100 ticks for electrical settling before measurement begins.

`ExitMeasurementMode` restores the motion system after measurement:
1. Re-syncs target to current encoder position (in case sleds drifted during measurement)
   to prevent jerk on restore.
2. Restores `SAP 6` to 25 (run current) and `SAP 7` to 8 (hold current).
3. Waits 50 ticks for the CL controller to stabilize at the current position.


**Step 5 — power off**
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

| Index | Name            | Contents                                                      |
|-------|-----------------|---------------------------------------------------------------|
| 0     | CALIB_POS_AXIS0 | Encoder position at calibration block, axis 0                 |
| 1     | CALIB_POS_AXIS1 | Encoder position at calibration block, axis 1                 |
| 2     | CALIB_POS_AXIS2 | Encoder position at calibration block, axis 2                 |
| 3     | axis0Done       | Temporary done flag used by `StartCalibrationSimultaneousAxis` (0/1, cleared on exit) |
| 4     | axis1Done       | Temporary done flag used by `StartCalibrationSimultaneousAxis` (0/1, cleared on exit) |
| 5     | axis2Done       | Temporary done flag used by `StartCalibrationSimultaneousAxis` (0/1, cleared on exit) |

User variables persist as long as the board is powered. Calibrating one axis does
not overwrite the others. Indices 3/4/5 are only meaningful during execution of
`StartCalibrationSimultaneousAxis` and are used internally to track which axes have
already stalled and been saved. Both `StartCalibration2` and
`StartCalibrationSimultaneousAxis` write to the same indices 0/1/2, so `StartMove2`
works unchanged after either calibration routine.

---

## Hard stop reproducibility measurements

Scale: 1 motor turn = 5 mm = 51,200 microsteps → 1 ustep ≈ 0.0000977 mm

### 1st hard stop — SAP 17 = 51,200 pps² (initial value, not yet changed)

| Sled |Block initialpos (encoder) | Target   |Encoder after 1st hard stop | Steps moved |
|------|---------------------------|----------|----------------------------|-------------|
| 0    | 501,017                   | −500,000 | 345,395                    | 155,622     |
| 1    | 498,790                   | −500,000 | 343,168                    | 155,622     |
| 2    | 499,020                   | −500,000 | 346,086                    | 152,934     |

sleds deviation after hard stop: 155,622 − 152,934 = **2,688 usteps = 0.26 mm**

`EmergencyStop2` raises SAP 17 to 1,000,000 during hard stop. `RecoverDeceleration` then restores it to 51,200.

---

### 2nd hard stop — comparing two SAP 17 strategies


| Sled | Target   | Encoder after 2nd hard stop | Steps moved from copper block |
|------|----------|-----------------------------|-------------------------------|
| 0    | −500,000 | 241,971                     | 259,046                       |
| 1    | −500,000 | 239,795                     | 258,995                       |
| 2    | −500,000 | 245,376                     | 253,644                       |

sleds deviation after hard stop: 259,046 − 253,644 = **5,402 usteps = 0.52 mm**

**Finish the move (the 500,000 steps) after the 2 hard stops**

| Sled | Final encoder pos | Steps moved from copper block |
|------|-------------------|-------------------------------|
| 0    | 1,075             | 499,942                       |
| 1    | −1,127            | 499,917                       |
| 2    | −666              | 499,686                       |

sleds deviation after the 2 hard stops and finishing the move: 499,942 − 499,686 = **256 usteps = 0.025 mm**

---

## Deprecated: StartCalibration + StartMove instead use StartCalibration2 + StartMove2

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

# TMCMCode_newversion.tmc — Julia-driven state machine

This script implements the same physical behaviour as `FullTest_CreatorMode.tmc` but
runs as a persistent loop on the TMCM board, controlled by a Julia interface via the
TMCL global parameter bank 2. Instead of uncommenting routines in Creator Mode, Julia
writes a command number to **GP 10 (bank 2)** and reads it back as 0 when the task is done.

---

## State machine command register (GP 10, bank 2)

Julia writes one of these values to GP 10 to trigger a routine. The board sets GP 10
back to 0 when the routine completes. Julia must wait for GP 10 = 0 before sending
the next command.

| GP 10 | Command | Notes |
|-------|---------|-------|
| 0  | Idle / complete | Board is ready for next command |
| 1  | PowerOn | Set motion params, sync encoder/target. Run once at startup. |
| 2  | StartInit | Load closed-loop PID parameters. |
| 3  | DisableClosedLoop | Wait for confirmed disable on all 3 axes. |
| 4  | EnableClosedLoop | Wait for confirmed enable on all 3 axes. |
| 5  | ReferenceZero | Set current sled positions as encoder origin (= 0). |
| 6  | StartCalibrationAxis0 | Move axis 0 down to block, save position. |
| 7  | StartCalibrationAxis1 | Move axis 1 down to block, save position. |
| 8  | StartCalibrationAxis2 | Move axis 2 down to block, save position. |
| 9  | StartMove | Move all 3 axes upward to `CALIB_POS - Target_Pos`. |
| 10 | PowerOff | Stop motors, disable CL, zero currents. |
| 11 | EnterMeasurementMode | Stop motors, zero currents, sync target. |
| 12 | ExitMeasurementMode | Restore currents, re-sync target. |
| 13 | MoveAxis0 | Move axis 0 to absolute encoder position in GP 0. |
| 14 | MoveAxis1 | Move axis 1 to absolute encoder position in GP 0. |
| 15 | MoveAxis2 | Move axis 2 to absolute encoder position in GP 0. |
| 16 | SimultaneousCalibration | All 3 axes descend together; each MST'd and saved independently on stall. Returns GP10=0 when all 3 done. |
| 99 | Error (EmergencyStop) | Set by board on hard stop. Board loops waiting for next Julia command. |
| 999 | EndLoop | Stop the TMCL program. |

---

## Data registers (bank 2)

Julia writes these before sending the relevant command.

| GP index | Name | Used by |
|----------|------|---------|
| 0  | Target_Pos | Offset above block in microsteps (command 9). Absolute target for commands 13/14/15. |
| 4  | Max_Speed | Velocity for all moves (write before command 1 or 9). |
| 53 | CALIB_POS_AXIS0 | Encoder position at block, axis 0 (written by commands 6 and 16). |
| 54 | CALIB_POS_AXIS1 | Encoder position at block, axis 1 (written by commands 7 and 16). |
| 55 | CALIB_POS_AXIS2 | Encoder position at block, axis 2 (written by commands 8 and 16). |
| 56–58 | CALIB_DONE_AXIS0–2 | Temporary done flags used internally by command 16. Cleared on exit. |

---

## Normal startup sequence (equivalent to Step 1 in FullTest)

```
SGP 10, 2, 1   # PowerOn      → wait GP10 = 0
SGP 10, 2, 2   # StartInit    → wait GP10 = 0
SGP 10, 2, 3   # DisableCL    → wait GP10 = 0
SGP 10, 2, 4   # EnableCL     → wait GP10 = 0
SGP 10, 2, 5   # ReferenceZero → wait GP10 = 0
```

## Calibration + move (equivalent to Steps 2B + 3B in FullTest)

```
SGP 10, 2, 16  # SimultaneousCalibration → wait GP10 = 0
SGP 10, 2, 9   # StartMove              → wait GP10 = 0
```

Or calibrate one axis at a time:
```
SGP 10, 2, 6   # axis 0 → wait GP10 = 0
SGP 10, 2, 7   # axis 1 → wait GP10 = 0
SGP 10, 2, 8   # axis 2 → wait GP10 = 0
SGP 10, 2, 9   # StartMove → wait GP10 = 0
```

## Hard stop recovery

If a hard stop occurs during StartMove (command 9), the board sets GP10 = 99 and
waits. Julia detects GP10 = 99 and can immediately send command 16 or 6/7/8 to
re-calibrate — no Step 1 needed as long as the board has not been power-cycled.

## Behaviour equivalence with FullTest_CreatorMode.tmc

Both scripts implement identical physical routines. The only difference is how they
are driven: FullTest requires manual uncomment/run in Creator Mode per step; this
script runs autonomously and accepts commands from Julia over the GP register
interface. The calibration logic (simultaneous 3-axis descent with per-axis
independent monitoring, immediate MST on stall) is identical.

---

## Julia interface — tmcl_control_layer.jl

`tmcl_control_layer.jl` wraps `TrinamicMotionControl.jl` to expose the state machine
commands as plain Julia functions. It uses two TMCL opcodes internally:

| TMCL opcode | Julia call | Direction |
|---|---|---|
| SGP (9) | `set_global_parameter(dev, gp, value)` | Julia → board |
| GGP (10) | `get_global_parameter(dev, gp)` | board → Julia |

`wait_for_idle(dev)` polls GP 10 every 100 ms until the board writes it back to 0.
Always call it after every command — the board is still executing while GP 10 ≠ 0.

### CSUB → Julia translation

Each `CSUB` line in `FullTest_CreatorMode.tmc` maps directly to one Julia function call:

| `FullTest_CreatorMode.tmc` | Julia | GP 10 sent |
|---|---|---|
| `CSUB PowerOn` | `power_on(dev)` | 1 |
| `CSUB StartInit` | `start_init(dev)` | 2 |
| `CSUB DisableClosedLoop` | `disable_closed_loop(dev)` | 3 |
| `CSUB EnableClosedLoop` | `enable_closed_loop(dev)` | 4 |
| `CSUB ReferenceZero` | `reference_zero(dev)` | 5 |
| `CSUB StartCalibrationSimultaneousAxis` | `calibrate_simultaneous(dev)` | 16 |
| `CSUB StartMove2` | `move_to(dev, 500000, 51200)` | 9 (writes GP0, GP4 first) |
| `CSUB EnterMeasurementMode` | `enter_measurement_mode(dev)` | 11 |
| `CSUB ExitMeasurementMode` | `exit_measurement_mode(dev)` | 12 |
| `CSUB PowerOff` | `power_off(dev)` | 10 |

**Key difference from `StartMove2`:** `StartMove2` hardcodes −500,000 as the upward
offset. The Julia `move_to(dev, position, speed)` writes `position` to GP 0 before
triggering StartMove (command 9), so the offset is a parameter. `move_to(dev, 500000, 51200)`
is exactly equivalent to `CSUB StartMove2`.

### Single-axis absolute moves (no Creator Mode equivalent)

To re-level one axis independently, write the absolute encoder target to GP 0 and
call `move_axis_to(dev, axis, position, speed)` (triggers commands 13/14/15).

### Complete measurement sequence

See `ScanSequence.jl` for a ready-to-run script. The sequence is:

```julia
# ── startup (once per power-cycle) ───────────────────────────────────
power_on(dev);             wait_for_idle(dev)
start_init(dev);           wait_for_idle(dev)
disable_closed_loop(dev);  wait_for_idle(dev)
enable_closed_loop(dev);   wait_for_idle(dev)
reference_zero(dev);       wait_for_idle(dev)   # sleds must be above blocks

# ── calibrate + move to first position ───────────────────────────────
calibrate_simultaneous(dev);        wait_for_idle(dev)
move_to(dev, 500_000, 51_200);      wait_for_idle(dev)

# ── scan loop ─────────────────────────────────────────────────────────
for offset in scan_points
    move_to(dev, offset, 51_200);       wait_for_idle(dev)
    enter_measurement_mode(dev);        wait_for_idle(dev)
    # ... acquire data ...
    exit_measurement_mode(dev);         wait_for_idle(dev)
end

power_off(dev); wait_for_idle(dev)
```

`reference_zero` must be called **before** calibration (while sleds are above the
blocks) and must never be called again after `calibrate_simultaneous`. The calibration
positions (GP 53/54/55) remain valid for any subsequent `move_to` calls without
re-calibrating, as long as the board is not power-cycled.