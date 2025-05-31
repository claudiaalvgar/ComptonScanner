HV = 3000
T = -181.6
adc = "192.168.2.178"

@info "Check if the filter script is running correctly"

# increase measurement times towards the center
# to compensate for loss in solid angle and due
# to additional scatters in the detector
measurement_times = Dict(
 0 => 83100,
 2 => 72000,
 4 => 62400,
 6 => 54000,
 8 => 46800,
10 => 40500,
12 => 35100,
14 => 30600,
16 => 26400,
18 => 22800,
20 => 19800,
22 => 17100,
24 => 15000,
26 => 12900,
28 => 11100,
30 =>  9600,
32 =>  8400,
34 =>  7200,
36 =>  7200
)

function copy_to_ceph(times = 2)
    if !isdir("../savedir/conv_data/$(HV)V") 
	@info "Creating directory savedir/conv_data/$(HV)V"
        mkdir("../savedir/conv_data/$(HV)V") 
    end
    for i in 1:times
	    for f in filter!(x -> endswith(x, "filtered.h5") && occursin("HV_$(HV)V", x), readdir("../conv_data/"))
	@info "Moving $(f) to ceph"
	mv("../conv_data/"*f, "../savedir/conv_data/$(HV)V/"*f)
    end
    end
end

function copy_to_ceph(times = 2)
    for i in 1:times
	for f in filter!(x -> startswith(x, "bkg_"), readdir("../conv_data/"))
	    @info "Moving $(f) to ceph"
            mv("../conv_data/"*f, "../savedir/cal_data/"*f)
	end
        for f in filter!(x -> endswith(x, "filtered.h5"), readdir("../conv_data/"))
	    @info "Moving $(f) to ceph"
            mv("../conv_data/"*f, "../savedir/conv_data/"*f)
        end
    end
end


#=
HorAbsMM(200,motor)
RotAbsDeg(0,motor)
Calibrate(motor)

cd(".."); load_3000_settings(adc); cd("raw_data")
take_data_hpge_onlyj(7200, T+273.15, motor, bkg = true, time_chunks = 300, HV = HV, adc = adc, enable_jumbo_frames = true)
=#

cd(".."); load_1200_settings(adc); cd("raw_data")
RotAbsDeg(0,motor)
Calibrate(motor)
Calibrate_Hor(motor)
for phi in (178.5, 178.5+45,)#, 178.5+22.5)
RotAbsDeg(phi,motor)
#copy_to_ceph()

for R in 36:-2:20
    #if phi == 178.5 || R >= 30 continue end
    HorAbsMM(81.8 - R,motor)
    take_data_hpge_plus_2cztj(measurement_times[R], T+273.15, motor, time_chunks = 300, HV = HV, adc = adc, enable_jumbo_frames = true)
    # copy_to_ceph()
end
end

HorAbsMM(200,motor)
RotAbsDeg(0,motor)
# copy_to_ceph()

@info "Depletion bubble scan finished"
