# Compton Scanner — TMCM-3351 Motor Controller Scripts

Hardware: TMCM-3351 3-axis closed-loop stepper motor controller.
Three sleds move vertically. Positive encoder direction = downward, negative = upward.

---

## Repository files

**Loop mode — Julia-driven (active workflow)**

| File | Type | Purpose |
|------|------|---------|
| `TMCMCode_newversion.tmc` | TMCL firmware | Persistent state machine running on the board. Loaded once via TMCL-IDE; auto-starts on every power-on. Controlled by Julia via GP 10. |
| `tmcl_control_layer.jl` | Julia module | Full API wrapping every board command as a named Julia function. Included by all scripts below. |
| `ScanSequence.jl` | Julia script | Normal session: startup → calibration → move. Use after a clean power-off or at the start of a measurement day. |
| `AfterRedButton_CodeLooping.jl` | Julia script | Resume after a red-button press/unpress **with USB still connected**. Calibration and encoder positions survive in RAM; only `startup!` is required. |
| `After_UnplugBoard.jl` | Julia script | Full recovery after complete power loss (board unplugged, or red button pressed with USB also disconnected). Must reload TMCL code, call `RefZero` once, then calibrate. |

**Creator Mode — manual TMCL-IDE workflow (legacy)**

| File | Type | Purpose |
|------|------|---------|
| `FullTest_CreatorMode.tmc` | TMCL script | Self-contained script for TMCL-IDE Creator Mode. No Julia required. Uncomment the step you want and execute. Used for initial hardware bring-up and hard-stop reproducibility tests. |

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
runs as a **persistent loop** on the TMCM board, controlled by Julia via the TMCL
global parameter bank 2.  Instead of uncommenting routines in Creator Mode, Julia
writes a command number to **GP 10 (bank 2)** and reads it back as 0 when the task
is done.  The program auto-starts after every power-on (SGP 77, Bank 0 = 1 stored in
EEPROM).

### Architecture

```
Julia                           Board (TMCMCode_newversion.tmc)
─────                           ──────────────────────────────
SGP 10, 2, N  ────────────────▶  GGP TMCM_Command, 2
                                  COMP N  →  dispatch to routine
                                  routine executes
                                  SGP 10, 2, 0
GGP 10 == 0   ◀─────────────────  (idle, ready for next command)
```

### Safety init on every program start

On every program start — including after a red-button press/unpress — the firmware
immediately executes before entering the main loop:

```tmcl
SAP 129, 0, 0   // disable closed-loop axis 0
SAP 129, 1, 0   // disable closed-loop axis 1
SAP 129, 2, 0   // disable closed-loop axis 2
SAP 6, 0, 0     // zero run current axis 0  (and 1, 2)
SAP 7, 0, 0     // zero standby current axis 0  (and 1, 2)
```

This guarantees all axes are de-energized and CL is disabled whenever the board
restarts.  The self-locking lead-screw spindles hold the sled positions without
motor current.  Julia's `startup!` re-applies currents and re-enables CL.

---

## State machine command register (GP 10, bank 2)

Julia writes one of these values to GP 10 to trigger a routine.  The board sets
GP 10 back to 0 when the routine completes.  Julia must wait for GP 10 = 0 before
sending the next command (use `wait_for_idle(dev)`).

| GP 10 | Routine name | Julia function | Notes |
|-------|-------------|---------------|-------|
| 0 | Idle | — | Board is ready for the next command |
| 1 | PowerOn | `power_on(dev)` | Write motion params (GP 4/5/6/7/17/210) to all axes via AAP; sync encoder→actual→target |
| 2 | StartInit | `start_init(dev)` | Write all closed-loop PID params (GP 108–126/212/213) to all axes via AAP |
| 3 | DisableClosedLoop | `disable_closed_loop(dev)` | SAP 129,x,0; polls AP 133 until confirmed disabled on all 3 axes |
| 4 | EnableClosedLoop | `enable_closed_loop(dev)` | SAP 129,x,1; polls AP 133 until confirmed enabled on all 3 axes |
| 5 | ReferenceZero | `reference_zero(dev)` | SAP 209,x,0 — zero encoder at current position; sync actual and target. **Only once after unplugging** |
| 6 | CalibrateAxis0 | `calibrate_axis(dev, 0)` | Descend axis 0 to block; MST on stall; save encoder pos → GP 53 |
| 7 | CalibrateAxis1 | `calibrate_axis(dev, 1)` | Descend axis 1 to block; MST on stall; save encoder pos → GP 54 |
| 8 | CalibrateAxis2 | `calibrate_axis(dev, 2)` | Descend axis 2 to block; MST on stall; save encoder pos → GP 55 |
| 9 | StartMove | `move_all_axes_to(dev, nsteps, speed)` | Move all 3 axes to `nsteps` microsteps **above the calibration block** (Julia reads GP 53/54/55, computes `calib_pos − nsteps`, writes absolute targets to GP 59/60/61) |
| 10 | PowerOff | `power_off(dev)` | MST all axes; disable CL; zero run and standby currents |
| 11 | EnterMeasurementMode | `enter_measurement_mode(dev)` | MST all axes; sync target to encoder; zero currents — eliminates motor EMI |
| 12 | ExitMeasurementMode | `exit_measurement_mode(dev)` | Re-sync target to encoder; restore currents (run=25, standby=8) |
| 13 | MoveAxis0 | `move_absolute_axis_to(dev, 0, pos, speed)` | Move axis 0 to `pos` microsteps above the **encoder zero set by `ReferenceZero`** (positive = down, negative = up relative to that origin) |
| 14 | MoveAxis1 | `move_absolute_axis_to(dev, 1, pos, speed)` | Move axis 1 to `pos` microsteps above the **encoder zero set by `ReferenceZero`** |
| 15 | MoveAxis2 | `move_absolute_axis_to(dev, 2, pos, speed)` | Move axis 2 to `pos` microsteps above the **encoder zero set by `ReferenceZero`** |
| 16 | SimultaneousCalibration | `calibrate!(dev)` | All 3 axes descend together in a round-robin poll loop; each is MST'd and saved independently on stall; GP10=0 when all 3 done |
| 99 | Error / EmergencyStop | — | Set by board on hard stop; waits for next Julia command |
| 999 | EndLoop | `end_program(dev)` | MST all axes; STOP — terminates the TMCL program |

---

## GP Bank 2 data registers

Julia writes these **before** sending the relevant command.

**Memory types and what survives each power event:**

**Hardware note — two separate power domains:**

The TMCM-3351 has two independent power supplies:

- **Motor supply** — the high-voltage/high-current rail that drives the motor coils
  and encoder interfaces.  The red button cuts this rail.
- **Logic supply** — the MCU, RAM, and USB interface.  When the board is connected
  to a PC via USB, the bus provides ~0.5 V which is enough to keep the MCU alive even
  when the motor supply is cut.

This means a red-button press/unpress is **not a full power-off** — it is a
partial-power state where the MCU and its RAM remain live while the motion hardware
is dead.  A full unplug (or powering off the PC-side USB) is the only event that
actually clears the MCU RAM.

The small encoder drift observed after a red-button press (~1500 usteps) comes from
the closed-loop disable/enable cycle: the safety init disables CL and zeros currents,
then `startup!` disables and re-enables CL again.  Each time CL is disabled the motor
is no longer actively held at its target position and the sled can move slightly under
gravity or mechanical play before CL is restored.

**Consequence: unplugging USB after the red button is equivalent to a full unplug.**
If the USB cable is disconnected while the motor supply is also off (i.e. after
pressing the red button), the logic supply drops, the MCU RAM is cleared, and all
AP values — including encoder positions — are lost.  This scenario is identical to
unplugging everything: the TMCL program must be reloaded, `RefZero` must be called
once to re-establish the encoder zero, and a full calibration is required.  The only
thing that would still survive is the EEPROM-backed calibration positions (GP 53/54/55
saved by `calibrate!`), but without a valid encoder zero reference those positions
are meaningless until `RefZero` is run again.

The TMCM-3351 has two distinct memory spaces with different survival rules:

- **Global Parameters (GP, Bank 2) — board RAM**, readable/writable via GGP/SGP.
  Indices 0–55 *can* be saved to EEPROM with the STGP opcode, but they are not
  saved automatically.  `calibrate!` explicitly calls STGP on GP 53/54/55 so the
  calibration block positions survive a full power cut.  All other GP values (motion
  params, PID params, move targets) are not STGP'd and are rewritten by Julia at the
  start of every session via `startup!`.

- **Axis Parameters (AP) — axis-local RAM**, readable/writable via GAP/SAP.  AP values
  like closed-loop enable (AP 129), run/standby current (AP 6/7), and encoder position
  (AP 209) **survive a red-button press/unpress** because the MCU RAM never loses
  power (USB keeps the logic supply alive).  They are lost only on a full unplug.

**Why closed-loop is DISABLED after a red-button press/unpress** despite AP values
surviving in RAM:

The red button restarts the TMCL program from the beginning.  The safety-init block
at the top of `TMCMCode_newversion.tmc` runs unconditionally before the main loop and
explicitly overwrites those AP values:

```tmcl
SAP 129, 0, 0   // disable closed-loop axis 0  (overwrites whatever was in AP 129)
SAP 6,   0, 0   // zero run current axis 0
SAP 7,   0, 0   // zero standby current axis 0
```

CL is disabled not because the AP value was lost, but because the firmware
deliberately forces it off for safety on every restart.  Encoder positions (AP 209)
are intentionally left untouched by the safety init — they persist with a small
mechanical drift (~1500 usteps) while the motors were de-energized.

| Value | Red button press/unpress | Full unplug |
|-------|--------------------------|-------------|
| Calibration positions GP 53/54/55 | **Yes** — GP Bank 2 RAM + EEPROM backup | **Yes** — EEPROM backup by `calibrate!` |
| Encoder positions AP 209 | **Yes** — AP RAM survives; small drift expected | **No** — RAM cleared; random on boot |
| Closed-loop enable AP 129 | AP survives but **firmware safety init disables it** | No — RAM cleared, safety init disables it |
| Run/standby current AP 6/7 | AP survives but **firmware safety init zeros them** | No — RAM cleared, safety init zeros them |
| CL PID params AP 108–126 | **Yes** — AP RAM survives; `startup!` rewrites anyway | No — RAM cleared; `startup!` required |
| TMCL program code | **Yes** — EEPROM | **No** — must reload via TMCL-IDE |

This is why the startup sequence after a red button is shorter than after unplugging:
calibration positions and encoder zero reference are still valid, but `startup!` is
always required to re-apply currents and re-enable closed loop.

`calibrate!` explicitly saves GP 53/54/55 to EEPROM (STGP opcode 11) so calibration
positions survive a full power cut.

| GP index | Julia constant | Written by | Read by |
|----------|---------------|-----------|--------|
| 0 | `GP_TARGET_POS` | Julia | MoveAxis0/1/2 (absolute encoder target) |
| 4 | `GP_MAX_SPEED` | Julia | PowerOn, StartMove, MoveAxis0/1/2, SimultaneousCalibration |
| 5 | `GP_MAX_ACCELERATION` | Julia | PowerOn |
| 6 | `GP_MAX_CURRENT` | Julia | PowerOn |
| 7 | `GP_STANDBY_CURRENT` | Julia | PowerOn |
| 10 | `GP_TMCM_COMMAND` | Julia (trigger) / board (clear to 0) | Main dispatch loop |
| 17 | `GP_MAX_DECELERATION` | Julia | PowerOn |
| 53 | `GP_CALIB_POS_AXIS0` | Board (calibration routines) | StartMove, `move_all_axes_to` |
| 54 | `GP_CALIB_POS_AXIS1` | Board (calibration routines) | StartMove, `move_all_axes_to` |
| 55 | `GP_CALIB_POS_AXIS2` | Board (calibration routines) | StartMove, `move_all_axes_to` |
| 56–58 | `GP_CALIB_DONE_AXIS0–2` | Board (internal) | SimultaneousCalibration done flags; cleared on exit |
| 59–61 | `GP_MOVE_TARGET_AXIS0–2` | Julia | StartMove (absolute targets = `calib_pos − offset`) |
| 108–126 | CL PID parameters | Julia | StartInit |
| 210 | `GP_ENCODER_RESOLUTION` | Julia | PowerOn |
| 212–213 | `GP_MAX_ENCODER/VELOCITY_DEVIATION` | Julia | StartInit |

---

## Behaviour equivalence with FullTest_CreatorMode.tmc

Both scripts implement identical physical routines.  The difference is the driving
mechanism: FullTest requires manual uncomment/run in Creator Mode per step;
TMCMCode_newversion runs autonomously and accepts commands over the GP register
interface.  The calibration logic (simultaneous 3-axis descent, round-robin poll,
immediate MST on stall) is identical.

| `FullTest_CreatorMode.tmc` CSUB | Julia function | GP 10 |
|----------------------------------|---------------|-------|
| `CSUB PowerOn` | `power_on(dev)` | 1 |
| `CSUB StartInit` | `start_init(dev)` | 2 |
| `CSUB DisableClosedLoop` | `disable_closed_loop(dev)` | 3 |
| `CSUB EnableClosedLoop` | `enable_closed_loop(dev)` | 4 |
| `CSUB ReferenceZero` | `reference_zero(dev)` | 5 |
| `CSUB StartCalibrationSimultaneousAxis` | `calibrate_simultaneous(dev)` | 16 |
| `CSUB StartMove2` (−500,000) | `move_all_axes_to(dev, 500_000, 51_200)` | 9 |
| `CSUB EnterMeasurementMode` | `enter_measurement_mode(dev)` | 11 |
| `CSUB ExitMeasurementMode` | `exit_measurement_mode(dev)` | 12 |
| `CSUB PowerOff` | `power_off(dev)` | 10 |

`StartMove2` hardcodes −500,000.  `move_all_axes_to(dev, nsteps, speed)` is
parameterized: Julia reads GP 53/54/55, computes per-axis absolute targets
(`calib_pos − nsteps`), writes them to GP 59/60/61, and triggers command 9.

---

## Julia interface — tmcl_control_layer.jl

`tmcl_control_layer.jl` wraps `TrinamicMotionControl.jl` and exposes every board
routine as a named Julia function.  Two TMCL opcodes are used:

| TMCL opcode | Julia call | Direction |
|-------------|-----------|----------|
| SGP (9) | `set_global_parameter(dev, gp, value)` | Julia → board |
| GGP (10) | `get_global_parameter(dev, gp)` | board → Julia |

`wait_for_idle(dev)` polls GP 10 every 100 ms until the board clears it to 0
(timeout 60 s).  **Always call it after every command** — the board is still
executing its routine while GP 10 ≠ 0.

### High-level composite functions

| Function | Sequence | Notes |
|----------|---------|-------|
| `startup!(dev)` | `power_on` → `start_init` → `disable_closed_loop` → `enable_closed_loop` | Once per power-cycle, before calibration. Sleds must be physically above the calibration blocks. |
| `calibrate!(dev)` | `calibrate_simultaneous` → STGP 53/54/55 to EEPROM | Can be re-run as many times as needed within a session. |
| `move_and_measure!(dev, nsteps, speed)` | `move_all_axes_to` → `enter_measurement_mode` | Move to scan position and de-energize motors. |
| `end_measurement!(dev)` | SAP current restore → `exit_measurement_mode` | Restore currents via SAP (more reliable than AAP/GGP with CL active). |
| `shutdown!(dev)` | `power_off` | Clean pre-power-off: MST, disable CL, zero currents. |
| `RefZero_run_only_once_after_unplugging_board!(dev)` | `reference_zero` | **Only after full power loss** (board unplugged, or red button pressed with USB also disconnected) — zeros encoder at current sled positions. Not needed after a red-button press/unpress with USB still connected, because the encoder positions survive in MCU RAM. |

### Diagnostic functions

| Function | Returns | Description |
|----------|---------|-------------|
| `read_axis_status(dev)` | `(calib_pos, encoder_pos)` | Logs GP 53/54/55 (calibration block positions) and AP 209 (current encoder positions) for all 3 axes. After a successful `calibrate!`, these two sets of values should be identical. |
| `read_closed_loop_status(dev)` | `(axis0, axis1, axis2)` Booleans | Logs ENABLED/DISABLED for each axis (AP 129). |
| `board_status(dev)` | named tuple | Logs supply voltage [V], temperature [°C/K], run current, standby current. |
| `check_program_looping(dev)` | `Bool` | Sends `end_program`, waits 300 ms, checks if GP 10 was cleared. Returns `true` if a TMCL program was looping. |

---

## Startup scenarios

### Scenario A — Full power loss (`After_UnplugBoard.jl`)

**When this applies:** the board was fully unplugged, OR the red button was pressed
**and** the USB cable was also disconnected (or the PC was off).  In both cases the
MCU RAM is cleared — there is no USB supply keeping the logic alive — so everything
is lost: the TMCL program is gone, encoder zero reference is gone, and all AP values
(encoder positions, CL state, currents) are gone.  Only the EEPROM-backed calibration
positions (GP 53/54/55) could technically survive, but without a valid encoder zero
reference they are meaningless.  **Sleds must be above the calibration blocks before
running this.**

```julia
# 1. Load TMCMCode_newversion.tmc onto the board via TMCL-IDE (Creator Mode → upload)

# 2. Run After_UnplugBoard.jl
dev = connect_board(BOARD_IP, BOARD_PORT)
sleep(2.0)

# Verify state: random values expected, CL must be DISABLED
read_axis_status(dev)
read_closed_loop_status(dev)    # → DISABLED (firmware disabled on startup)

startup!(dev)                   # PowerOn → StartInit → DisableCL → EnableCL

# Set the encoder zero at the current sled positions — ONCE ONLY after unplugging
RefZero_run_only_once_after_unplugging_board!(dev)

read_closed_loop_status(dev)    # → ENABLED

calibrate!(dev)                 # all 3 axes descend → stall → positions saved to EEPROM

move_all_axes_to(dev, 500_000, 51_200); wait_for_idle(dev)
```

**Why `RefZero` must only be called once after unplugging:**
`ReferenceZero` (GP 10 = 5) resets the encoder to 0 at the current sled positions
and syncs actual and target registers — giving the CL controller a clean zero
reference.  Calling it again after calibration would reset the origin to the block
positions, corrupting the coordinate system and breaking hard-stop detection.

---

### Scenario B — Red button pressed and unpressed, USB still connected (`AfterRedButton_CodeLooping.jl`)

**When this applies:** the red button was pressed and unpressed **while the USB cable
remained connected to the PC**, AND `end_program` was **not** called before pressing
it (i.e. the TMCL program was still looping on the board at the moment of the press).
Because USB keeps the MCU logic supply alive, the MCU RAM is never cleared — encoder
positions, calibration positions, and CL PID parameters all survive.  The TMCL
program restarts from the top, runs the safety init (disables CL, zeros currents),
and re-enters the MainLoop.

**If `end_program` was called before pressing the red button:** the TMCL program is
already stopped and will not restart on its own when the red button is released
(no MCU reset occurred).  In that case use **Scenario C** instead.

**Verified measured behavior:**

| State | calib ax0 | calib ax1 | calib ax2 | encoder ax0 | encoder ax1 | encoder ax2 | CL |
|-------|-----------|-----------|-----------|-------------|-------------|-------------|----|
| Load tmcm code. Before red button | 293964 | 326093 | 299489 | −205945 | −173664 | −200263 | DISABLED |
| Press and After unpress red button (tmcm code looping is restarted) | 293964 | 326093 | 299489 | −207481 | −173689 | −199751 | **DISABLED** |
| After `startup!` | 293964 | 326093 | 299489 | −207232 | −173465 | −199552 | **ENABLED** |
| After `calibrate!` | 292966 | 326093 | 300262 | 292966 | 326093 | 300262 | ENABLED |

Encoder positions drift slightly (~1500 usteps ≈ 0.15 mm) during the red-button
period because CL is inactive and the sled is no longer actively held.  This is
normal.  After `calibrate!`, encoder positions match calibration positions exactly
— both columns show the same values.

This drift could in principle be eliminated by removing the `SAP 129, x, 0` lines
from the safety-init block at the top of `TMCMCode_newversion.tmc`, so that CL
remains enabled when the board restarts after a red-button press.  However, this
is intentionally not done because it would be dangerous:

- When the red button is pressed, motor power is cut abruptly.  The CL controller
  was actively driving the motor at the moment of cut; its integrator has accumulated
  error and its last commanded target is still stored in AP 0.
- When the red button is released and motor power returns, a CL controller that was
  never disabled would immediately command maximum current to drive the sled back to
  that target — a sudden, uncontrolled movement with no warning.
- The operator releasing the red button expects the system to be stationary and
  inert.  An emergency stop that re-energizes the motors automatically on release
  defeats the purpose of the stop.

Disabling CL in the safety init ensures that when power returns the sleds stay
exactly where they are until the operator explicitly calls `startup!` to restore
controlled motion.

```julia
dev = connect_board(BOARD_IP, BOARD_PORT)
sleep(2.0)

# Calib positions should still be present; encoder may have drifted; CL is DISABLED
read_axis_status(dev)
read_closed_loop_status(dev)

startup!(dev)                   # PowerOn → StartInit → DisableCL → EnableCL
                                # DO NOT call RefZero — encoder zero reference is still valid

read_axis_status(dev)
read_closed_loop_status(dev)    # → ENABLED

# Recalibrate (safe to run as many times as needed)
calibrate!(dev)

# or skip recalibration if read_axis_status shows calib_pos == encoder_pos

move_all_axes_to(dev, 500_000, 51_200); wait_for_idle(dev)
```

---

### Scenario C — Normal session, clean startup (`ScanSequence.jl`)

Board was powered off cleanly (`shutdown!` + `end_program`). Need to load again the TMCL code
that would start looping and waiting for Julia commands.

```julia
dev = connect_board(BOARD_IP, BOARD_PORT)
sleep(2.0)                      # let board reach MainLoop before sending commands

startup!(dev)                   # PowerOn → StartInit → DisableCL → EnableCL
calibrate!(dev)                 # simultaneous 3-axis calibration → EEPROM

const MOVE_NSTEPS     = 500_000  # microsteps above calibration block
const DEFAULT_MAX_SPEED = 51_200  # usteps/s

move_all_axes_to(dev, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)

# Optional: de-energize motors for low-noise HPGe data acquisition
# move_and_measure!(dev, MOVE_NSTEPS, DEFAULT_MAX_SPEED)   # move + enter measurement mode
# ... acquire data ...
# end_measurement!(dev)                                     # restore currents

# Optional: move a single axis to an absolute encoder position (re-leveling)
# move_absolute_axis_to(dev, 0, 100_000, DEFAULT_MAX_SPEED); wait_for_idle(dev)

shutdown!(dev)      # MST all, disable CL, zero currents
end_program(dev)    # stop the TMCL loop on the board
```

---

## Calibration and encoder zero — key rules

1. **`ReferenceZero` is only called once after unplugging the board (or with the red button pressed plus USB disconnected i.e. board unpowered)**, while sleds are
   above the blocks.  It sets encoder = 0 at the current sled positions.  After this,
   the zero reference is valid for the lifetime of the power-on session.

2. **`calibrate!` can be re-run as many times as needed** within a session.
   It descends all 3 axes simultaneously to their mechanical stops, saves encoder
   positions at each stop to GP 53/54/55, and writes them to EEPROM.

3. **After `calibrate!`, `calib_pos == encoder_pos` exactly.**
   `read_axis_status` showing identical values for both columns confirms a clean calibration.

4. **Calibration positions survive a red-button press/unpress (with USB connected)** (EEPROM).
   They do **not** survive unplugging the board or pressing the red button plus disconnecting the USB (encoder zero reference is lost).

5. **Never call `reference_zero` after calibration.**  The CL controller's internal
   commutation state would no longer match the new encoder = 0 reference, causing
   incorrect hard-stop detection and erratic motion.

---

## Measurement mode — EnterMeasurementMode / ExitMeasurementMode

`EnterMeasurementMode` (command 11) de-energizes all motors for low-noise HPGe acquisition:
1. MST all axes; polls `GAP 3` (actual velocity) until each axis confirms zero.
2. Waits 50 ticks for mechanical settling.
3. Syncs target (`AAP 0`) to current encoder (`GAP 209`) — prevents the CL controller
   from fighting to return to the old move target when current is restored.
4. Sets run current (`SAP 6`) and standby current (`SAP 7`) to 0 — stops all PWM
   switching, eliminating motor EMI during measurement.
5. Waits 100 ticks for electrical settling before measurement begins.

`ExitMeasurementMode` (command 12) restores the motion system:
1. Re-syncs target to current encoder position (accounts for any sled drift during
   measurement) — prevents jerk on restore.
2. Restores run current = 25 and standby current = 8.
3. Waits 50 ticks for CL to stabilise.

Note: `end_measurement!` in Julia uses SAP (direct axis parameter write) rather than
AAP/GGP to restore currents, because AAP/GGP is unreliable with CL active.

After `exit_measurement_mode` the system is fully operational — CL is still enabled
and currents are restored.  Because the sleds were moved upward before entering
measurement mode they are above the calibration blocks, so `calibrate!` can be called
again at any point after `exit_measurement_mode` without any additional steps.

---

## Clean shutdown procedure

Before pressing the red button to power off, always run:

```julia
shutdown!(dev)      # MST all axes, disable CL, zero currents
end_program(dev)    # stop the TMCL loop on the board
```

After `end_program` the TMCL program stops looping in the board.  If the red button is pressed
after `end_program` with USB still connected, no MCU reset occurs, so the program
does **not** restart.  A full power cycle is required to bring it back.

If `shutdown!` is skipped, the next startup still works correctly because the firmware
disables CL and zeros currents on every program start.  Calling `shutdown!` first is
still best practice — it leaves the board in a known idle state and avoids the CL
controller being active at the moment of power loss.

---

## Default motion parameters

| Julia constant | Default value | Units | AP / GP |
|---------------|--------------|-------|--------|
| `DEFAULT_MAX_SPEED` | 51,200 | usteps/s | AP 4 / GP 4 |
| `DEFAULT_MAX_ACCELERATION` | 51,200 | usteps/s² | AP 5 / GP 5 |
| `DEFAULT_MAX_DECELERATION` | 51,200 | usteps/s² | AP 17 / GP 17 |
| `DEFAULT_MAX_CURRENT` | 25 | % of max | AP 6 / GP 6 |
| `DEFAULT_STANDBY_CURRENT` | 8 | % of max | AP 7 / GP 7 |
| `DEFAULT_ENCODER_RESOLUTION` | 2000 | counts/rev | AP 210 / GP 210 |

Scale: 1 motor turn = 5 mm = 51,200 microsteps → **1 ustep ≈ 0.097 µm**

All defaults can be overridden via keyword arguments to `power_on(dev; ...)` and
`start_init(dev; ...)`.
