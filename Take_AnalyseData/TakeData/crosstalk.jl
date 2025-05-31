#take data to study the crosstalk between segments
#
HV = 3000
adc = "192.168.2.178"

function copy_to_ceph(times = 2)
    #if !isdir("../savedir/conv_data/$(HV)V") 
    #    @info "Creating directory savedir/conv_data/$(HV)V"
    #    mkdir("../savedir/conv_data/$(HV)V") 
    #end
    for i in 1:times
	    for f in filter!(x -> !startswith(x, "bkg") && endswith(x, "filtered.h5") && occursin("HV_$(HV)V", x), readdir("../conv_data/"))
	    @info "Moving $(f) to ceph"
	    mv("../conv_data/"*f, "../savedir/conv_data/"*f)
        end
    end
    for i in 1:times
	for f in filter!(x -> startswith(x, "bkg"), readdir("../conv_data/"))
	    @info "Moving $(f) to ceph"
	    mv("../conv_data/"*f, "../savedir/cal_data/"*f)
	end
    end
end

Calibrate_Hor(motor)
HorAbsMM(200, motor)
RotAbsDeg(0,motor)
Calibrate(motor)
#cd(".."); load_bkg_settings(); cd("raw_data")

# start background measurement
#take_data_hpge_onlyj(7200, -201.4+273.15, motor, bkg = true, time_chunks = 300, HV = HV, adc = adc, enable_jumbo_frames = true)


cd(".."); load_1200_settings(); cd("raw_data")
# take actual cross talk measurement
HorAbsMM(47,motor)
for phi in [52.7,112.2,171.3,232.9,292.1,352.5]
    RotAbsDeg(phi,motor)
    take_data_hpge_plus_2cztj(7200, -201.4+273.15, motor, time_chunks = 300, HV = HV, adc = adc, enable_jumbo_frames = true)
    copy_to_ceph()
end


HorAbsMM(200,motor)
RotAbsDeg(0,motor)
copy_to_ceph()

@info "Crosstalk measurement finished"
