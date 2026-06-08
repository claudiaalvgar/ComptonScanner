module TMCLControlLayer

export set_global_parameter,
       get_global_parameter,
       wait_for_idle,
       power_on,
       power_off,
       start_init,
       disable_closed_loop,
       enable_closed_loop,
       reference_zero,
       calibrate_axis,
       calibrate_simultaneous,
       enter_measurement_mode,
       exit_measurement_mode,
       move_axis_absolute,
       move_all_axes_to,
       move_absolute_axis_to,
       end_program,
       startup!,
       calibrate!,
       move_and_measure!,
       exit_measurement_mode!,
       shutdown!

using TrinamicMotionControl

# ============================================================
# IMPORTANT CONSTANT
# ============================================================
#=
TMCL protocol: Julia writes to GP 10 (Bank 2) to trigger routines in the
running TMCL state machine. The board polls GP 10 in its MainLoop, dispatches
to the matching routine, and writes GP 10 = 0 on completion. Julia polls with
wait_for_idle() to know when the board is done.

TMCL command numbers: 9 = SGP, 10 = GGP, both use Bank 2.
=#
const GP_BANK = 2   # must match TMCMCode_newversion.tmc (Bank 2)

# ============================================================
# LOW LEVEL WRAPPERS
# ============================================================

"""
Set global parameter (SGP)
"""
function set_global_parameter(dev, gp::Int, value::Int)
    return query(dev, 9, gp, GP_BANK, value)
end

"""
Get global parameter (GGP)
"""
function get_global_parameter(dev, gp::Int)
    return query(dev, 10, gp, GP_BANK, 0)
end

# State machine commands — GP10 values match TMCMCode_newversion.tmc
power_on(dev)                = set_global_parameter(dev, 10, 1)
start_init(dev)              = set_global_parameter(dev, 10, 2)
disable_closed_loop(dev)     = set_global_parameter(dev, 10, 3)
enable_closed_loop(dev)      = set_global_parameter(dev, 10, 4)
reference_zero(dev)          = set_global_parameter(dev, 10, 5)
calibrate_axis(dev, ax::Int) = set_global_parameter(dev, 10, 6 + ax )  # ax ∈ {0,1,2} → GP10 ∈ {6,7,8}
calibrate_simultaneous(dev)  = set_global_parameter(dev, 10, 16)
power_off(dev)               = set_global_parameter(dev, 10, 10)
enter_measurement_mode(dev)  = set_global_parameter(dev, 10, 11)
exit_measurement_mode(dev)   = set_global_parameter(dev, 10, 12)
move_axis_absolute(dev, ax::Int) = set_global_parameter(dev, 10, 13 + ax )  # ax ∈ {0,1,2} → GP10 ∈ {13,14,15}
end_program(dev)             = set_global_parameter(dev, 10, 999)

# ============================================================
# HIGH LEVEL COMMANDS
# ============================================================
function wait_for_idle(dev; gp::Int = 10)
    while true
        state = get_global_parameter(dev, gp)
        state == 0 && break
        sleep(0.1)
    end
end

"""
Move all 3 axes to an offset above the copper block calibration position.
GP0 = offset in microsteps (positive = upward), GP4 = max speed.
Requires a prior calibration.
"""
function move_all_axes_to(dev, position::Int, speed::Int)
    set_global_parameter(dev, 0, position)   # GP0 = offset above copper block
    set_global_parameter(dev, 4, speed)      # GP4 = max speed
    set_global_parameter(dev, 10, 9)         # GP10 = 9 → StartMove
end

"""
Move a single axis to an absolute encoder position.
ax ∈ {0,1,2}, position in encoder microsteps.
"""
function move_absolute_axis_to(dev, ax::Int, position::Int, speed::Int)
    set_global_parameter(dev, 0, position)   # GP0 = absolute encoder target
    set_global_parameter(dev, 4, speed)      # GP4 = max speed
    move_axis_absolute(dev, ax)              # GP10 = 13/14/15
end

# ─────────────────────────────────────────────────────────────────────────────
# startup!
# Must be called once per power-cycle, before calibration.
# Sleds must be physically above the calibration blocks before calling this.
# ─────────────────────────────────────────────────────────────────────────────
function startup!(dev)
    @info "PowerOn — set motion params, sync encoder/actual/target"
    power_on(dev);             wait_for_idle(dev)

    @info "StartInit — load closed-loop PID parameters"
    start_init(dev);           wait_for_idle(dev)

    @info "DisableClosedLoop"
    disable_closed_loop(dev);  wait_for_idle(dev)

    @info "EnableClosedLoop — clean CL init before any move"
    enable_closed_loop(dev);   wait_for_idle(dev)

    @info "ReferenceZero — set current sled positions as encoder origin"
    reference_zero(dev);       wait_for_idle(dev)

    @info "Startup complete."
end

# ─────────────────────────────────────────────────────────────────────────────
# calibrate!
# Descend all 3 axes simultaneously to the calibration blocks and save positions.
# Do not call reference_zero again after this.
# ─────────────────────────────────────────────────────────────────────────────
function calibrate!(dev)
    @info "SimultaneousCalibration — all 3 axes descend, stall, positions saved at GP 53/54/55"
    calibrate_simultaneous(dev); wait_for_idle(dev)
    @info "Calibration complete."
end

# ─────────────────────────────────────────────────────────────────────────────
# move_and_measure! and exit_measurement_mode!
# ─────────────────────────────────────────────────────────────────────────────
function move_and_measure!(dev, nsteps_to_move::Int, speed::Int)
    @info "Moving to scan position: $nsteps_to_move usteps above block"
    move_all_axes_to(dev, nsteps_to_move, speed); wait_for_idle(dev)

    @info "EnterMeasurementMode — stop motors, zero currents"
    enter_measurement_mode(dev); wait_for_idle(dev)

    @info "At measurement position."
end

function exit_measurement_mode!(dev)
    @info "ExitMeasurementMode — restore currents"
    exit_measurement_mode(dev); wait_for_idle(dev)
end
# ─────────────────────────────────────────────────────────────────────────────
# shutdown!
# ─────────────────────────────────────────────────────────────────────────────
function shutdown!(dev)
    @info "PowerOff"
    power_off(dev); wait_for_idle(dev)
    @info "Board powered off."
end

end # module
