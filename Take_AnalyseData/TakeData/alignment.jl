using GeDetK2Control

cd("/home/gelab/Measurements/ComptonScanner/Data/newData_temp")
include("/home/gelab/Measurements/ComptonScanner/sis3316_capture_chunking.jl")

motor = k2.mymotor()

# Calibrate_Hor(motor)
# RotAbsDeg(0,motor)
# Calibrate(motor)

for r = 0:30:350
    RotAbsDeg(r, motor)
    for h = vcat(44:1:54)
        HorAbsMM(h, motor)
        take_data_hpge_onlyj(30, 80, motor, HV = 3200, enable_jumbo_frames=false)
    end
end


HorAbsMM(200,motor)
RotAbsDeg(0,motor)

@info "Alignment scan finished"
