cd("/home/gelab/testJulia/ComptonScanner/NewComptonScanner")
using Pkg
Pkg.activate(".")
using TrinamicMotionControl
import TrinamicMotionControl: query, set_axis_parameter, get_axis_parameter

const BOARD_IP   = "gelab-serial01"
const BOARD_PORT = 2001
const GP_BANK = 2

# ── GP Bank 2 address constants ───────────────────────────────────────────────
# Mirror the variable declarations at the top of the TMC scripts so every
# set_global_parameter / get_global_parameter call uses a readable name.
const GP_TARGET_POS                     = 0
const GP_ACTUAL_POS                     = 1
const GP_TARGET_SPEED                   = 2
const GP_ACTUAL_SPEED                   = 3
const GP_MAX_SPEED                      = 4
const GP_MAX_ACCELERATION               = 5
const GP_MAX_CURRENT                    = 6
const GP_STANDBY_CURRENT                = 7
const GP_TMCM_COMMAND                   = 10
const GP_MAX_DECELERATION               = 17
const GP_CALIB_POS_AXIS0                = 53
const GP_CALIB_POS_AXIS1                = 54
const GP_CALIB_POS_AXIS2                = 55
const GP_CALIB_DONE_AXIS0               = 56
const GP_CALIB_DONE_AXIS1               = 57
const GP_CALIB_DONE_AXIS2               = 58
const GP_CL_GAMMA_VMIN                  = 108
const GP_CL_GAMMA_VMAX                  = 109
const GP_CL_MAXGAMMA                    = 110
const GP_CL_BETA                        = 111
const GP_CL_CURRENTMIN                  = 113
const GP_CL_CURRENTMAX                  = 114
const GP_CL_CORRECTION_VELOCITY_P       = 115
const GP_CL_CORRECTION_VELOCITY_I       = 116
const GP_CL_CORRECTION_VELOCITY_I_CLIP  = 117
const GP_CL_CORRECTION_VELOCITY_DV_CLK  = 118
const GP_CL_CORRECTION_VELOCITY_DV_CLIP = 119
const GP_CL_UPSCALE_DELAY               = 120
const GP_CL_DOWNSCALE_DELAY             = 121
const GP_CL_CORRECTION_POS              = 124
const GP_CL_MAX_CORRECTION_TOLERANCE    = 125
const GP_CL_STARTUP                     = 126
const GP_POS_WINDOW                     = 134
const GP_ENCODER_POS                    = 209
const GP_ENCODER_RESOLUTION             = 210
const GP_MAX_ENCODER_DEVIATION          = 212
const GP_MAX_VELOCITY_DEVIATION         = 213

# ── Default parameter values ──────────────────────────────────────────────────
# Match the SGP static-init values in the TMC scripts.
# Override via keyword arguments on power_on / start_init.
const DEFAULT_ENCODER_RESOLUTION             = 2000
const DEFAULT_MAX_SPEED                      = 51_200
const DEFAULT_MAX_ACCELERATION               = 51_200
const DEFAULT_MAX_DECELERATION               = 51_200
const DEFAULT_MAX_CURRENT                    = 25
const DEFAULT_STANDBY_CURRENT                = 8
const DEFAULT_CL_GAMMA_VMIN                  = 300_000
const DEFAULT_CL_GAMMA_VMAX                  = 600_000
const DEFAULT_CL_MAXGAMMA                    = 255
const DEFAULT_CL_BETA                        = 255
const DEFAULT_CL_CURRENTMIN                  = 50
const DEFAULT_CL_CURRENTMAX                  = 240
const DEFAULT_CL_CORRECTION_VELOCITY_P       = 3000
const DEFAULT_CL_CORRECTION_VELOCITY_I       = 20
const DEFAULT_CL_CORRECTION_VELOCITY_I_CLIP  = 10
const DEFAULT_CL_CORRECTION_VELOCITY_DV_CLK  = 0
const DEFAULT_CL_CORRECTION_VELOCITY_DV_CLIP = 100_000
const DEFAULT_CL_UPSCALE_DELAY               = 1000
const DEFAULT_CL_DOWNSCALE_DELAY             = 10_000
const DEFAULT_CL_CORRECTION_POS              = 65_536
const DEFAULT_CL_MAX_CORRECTION_TOLERANCE    = 100
const DEFAULT_CL_STARTUP                     = 25
const DEFAULT_POS_WINDOW                     = 100
const DEFAULT_MAX_ENCODER_DEVIATION          = 1000
const DEFAULT_MAX_VELOCITY_DEVIATION         = 30_000

function connect_board(ip::AbstractString, port::Int)
    dev = TMCLDevice("TMCM-3351", ip, port)
    @info "Connected to board at $ip:$port"
    return dev
end

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


dev = connect_board(BOARD_IP, BOARD_PORT)
sleep(2.0)  # allow board to reach MainLoop before sending commands

function wait_for_idle(dev; timeout_s::Float64 = 5.0)
    t0 = time()
    while true
        get_global_parameter(dev, GP_TMCM_COMMAND) == 0 && break
        time() - t0 > timeout_s && error("Board did not become idle within $(timeout_s)s — is the TMCL program running?")
        sleep(0.1)
    end
end

function power_on(dev;
        encoder_resolution = DEFAULT_ENCODER_RESOLUTION,
        max_speed          = DEFAULT_MAX_SPEED,
        max_acceleration   = DEFAULT_MAX_ACCELERATION,
        max_deceleration   = DEFAULT_MAX_DECELERATION,
        max_current        = DEFAULT_MAX_CURRENT,
        standby_current    = DEFAULT_STANDBY_CURRENT)
    set_global_parameter(dev, GP_ENCODER_RESOLUTION, encoder_resolution)
    set_global_parameter(dev, GP_MAX_SPEED,          max_speed)
    set_global_parameter(dev, GP_MAX_ACCELERATION,   max_acceleration)
    set_global_parameter(dev, GP_MAX_DECELERATION,   max_deceleration)
    set_global_parameter(dev, GP_MAX_CURRENT,        max_current)
    set_global_parameter(dev, GP_STANDBY_CURRENT,    standby_current)
    set_global_parameter(dev, GP_TMCM_COMMAND,       1)  # trigger board PowerOn
    wait_for_idle(dev)
end
power_on(dev)

#This stops the TMCM program looping on the board
end_program(dev) = set_global_parameter(dev, GP_TMCM_COMMAND, 999)
end_program(dev)

#Set speed via SGP and read speed via GGP : Global parameters set constant values
#query(dev, 9, GP_MAX_SPEED, GP_BANK, 51_200)
#query(dev, 10, GP_MAX_SPEED, GP_BANK, 0)

#Set speed via SAP and read speed via GAP : This changes motor axis values
#set_axis_parameter(dev, GP_MAX_SPEED, 0, 51_200) # Set speed for axis 0
#get_axis_parameter(dev, GP_MAX_SPEED, 0)         # Read speed for axis 0