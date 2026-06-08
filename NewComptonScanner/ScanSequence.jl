# ScanSequence.jl
# Complete startup + calibration + measurement scan sequence for the
# TMCM-3351 controlled by TMCMCode_newversion.tmc.

using TrinamicMotionControl
include("tmcl_control_layer.jl")
using .TMCLControlLayer

# ── board connection ──────────────────────────────────────────────────────────
const BOARD_IP   = "192.168.0.2"   # adjust to your board IP
const BOARD_PORT = 4016            # adjust to your board port

const DEFAULT_SPEED = 51_200   # usteps/s (1 rev/s): 51,200 usteps = 5 mm = 1 motor revolution.
const MOVE_NSTEPS = 500_000  # example offset above block for measurement position

function connect_board(; ip = BOARD_IP, port = BOARD_PORT)
    dev = TMCLDevice("TMCM-3351", ip, port)
    @info "Connected to board at $ip:$port"
    return dev
end


# ── Interactive use (REPL / included from another script) ────────────────────
#
   dev = connect_board()          # or: connect_board(ip="192.168.x.x", port=4016)
   startup!(dev)                  # PowerOn → StartInit → DisableCL → EnableCL → ReferenceZero
   calibrate!(dev)                # SimultaneousCalibration
   #move_and_measure!(dev, MOVE_NSTEPS, DEFAULT_SPEED)
   #exit_measurement_mode!(dev)
   move_all_axes_to(dev, MOVE_NSTEPS, DEFAULT_SPEED)
   #shutdown!(dev)
#
# ── Run directly ─────────────────────────────────────────────────────────────
#
#   julia ScanSequence.jl
#
# ─────────────────────────────────────────────────────────────────────────────

# ── scan configuration ────────────────────────────────────────────────────────
# Offsets above the copper block in microsteps (positive = upward).

#function run_full_scan(; ip = BOARD_IP, port = BOARD_PORT, move_steps = MOVE_NSTEPS, speed = DEFAULT_SPEED)
#    dev = connect_board(ip = ip, port = port)
#    startup!(dev)
#    calibrate!(dev)
#    move_and_measure!(dev, move_steps, speed)
#    exit_measurement_mode!(dev)
#    shutdown!(dev)
#end

# ─────────────────────────────────────────────────────────────────────────────
# Run when executed directly: julia ScanSequence.jl
# ─────────────────────────────────────────────────────────────────────────────
#if abspath(PROGRAM_FILE) == @__FILE__
#    run_full_scan()
#end
