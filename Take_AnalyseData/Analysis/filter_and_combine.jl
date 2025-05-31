include("filter.jl")
function filter_and_combine_data_2j(logdir::String, savedir::String; detname = "fadc", ch = 1:5, overwrite = false, delete_src_files = false, f_s = [0,0])

    if logdir[end] != '/'; logdir *= "/"; end
    if savedir[end] != '/'; savedir *= "/"; end

    @assert(isdir(savedir),"$savedir does not exist")
    @assert(isdir(savedir*"../raw_data/"),"$(savedir*"../raw_data/") does not exist")
    @assert(isdir(savedir*"../err_data/"),"$(savedir*"../err_data/") does not exist")

    #filenames = filter(x -> x[end-4:end] == "Z.dat", readdir(logdir))
    #filenames = filter(x -> endswith(x, "Z.dat"), readdir(logdir))


    for bkg in filter(x -> startswith(x,"bkg") && endswith(x, "Z.lh5"), readdir(logdir))
	mv(bkg, "../conv_data/"*bkg)
    end

    filenames = sort(filter(x -> !startswith(x, "bkg") && endswith(x, "Z.lh5"), readdir(logdir)), by = x -> match(r"T\d{6}Z", x).match[2:end-1])

    for filename00 in filenames

        #save to
        filename = replace(filename00, "-ICPC" => "")
        filename = savedir*replace(filename, ".lh5" => "-filtered.h5")

        if !overwrite && filename in savedir.*readdir(savedir);
            @info("File already exists. Skipping...")
            continue;
        end

        filename01 = replace(filename00, "ICPC" => "CZT1")
        filename01 = replace(filename01, ".lh5" => ".h5")

        filename02 = replace(filename00, "ICPC" => "CZT2")
        filename02 = replace(filename02, ".lh5" => ".h5")

        println()
        @info "Filtering $filename00"

        if startswith(filename00, "bkg")
            mv(logdir*filename00, savedir*"../raw_data/"*filename00, force=true)
            try
                rm(logdir*filename01)
            catch
                nothing
            end
            try
                rm(logdir*filename02)
            catch
                nothing
            end
            continue;
        end

        #read in data
        @info "Reading in data"
	ICPC_raw = read_data_from_julia(logdir*filename00, ch = ch[1], sync = [9,10])
        #check_results(ICPC_raw)

        czt_raw1 = HDF5.h5open(logdir*filename01, "r") do input
            readdata(input, "data_raw")
        end
filter_and_combine_data_2jt[czt_raw1.evt_issync]
        CZT_old_sync2 = czt_raw2.evt_t[czt_raw2.evt_issync]
        #=
        events = (dut = ICPC_raw, cam = czt_raw)
        ICPC_raw = nothing
        czt_raw = nothing
        =#

        #align timestamps in CZT data
        fit_went_well = [true]
        @info "Correcting timestamps"
	czt_corr1 = new_correct_time_to_struck!(ICPC_raw, czt_raw1, core = ch[1], channel = 9, fit_went_well = fit_went_well)
	czt_corr2 = new_correct_time_to_struck!(ICPC_raw, czt_raw2, core = ch[1], channel = 10, fit_went_well = fit_went_well)

        if fit_went_well[1] == false
            @warn "Sync fit failed. Moving file and associated CZT file to ../err_data"
            mv(logdir*filename00, savedir*"../err_data/"*filename00, force=true)
            mv(logdir*filename01, savedir*"../err_data/"*filename01, force=true)
            mv(logdir*filename02, savedir*"../err_data/"*filename02, force=true)
            f_s[1] = f_s[1] + 1
            open(savedir*"../err_data/filter_logs.txt", "a") do io
                write(io, "$(now())\t$filename00\tSync fit failed\n");
            end
            continue
        end

        # Find time coincident events in BEGe and CZT1
        @info "Finding common events"
        df_rege = ICPC_raw[findall(x -> x in ch, ICPC_raw.chid)]
        df_czt1 = czt_corr1[findall(x -> !x, czt_corr1.evt_issync)]; czt_corr1 = nothing
        df_czt2 = czt_corr2[findall(x -> !x, czt_corr2.evt_issync)]; czt_corr2 = nothing
        common_idxs_r01, common_idxs_p01 = my_new_find_common_events((df_rege, df_czt1), 5e-5u"s")
        common_idxs_r02, common_idxs_p02 = my_new_find_common_events((df_rege, df_czt2), 5e-5u"s")
        common_idxs = unique(sort(vcat(common_idxs_r01, common_idxs_r02)))

        #save coincident events
        dfc_r01 = df_rege[common_idxs]
        czt1 = df_czt1[common_idxs_p01]
        czt2 = df_czt2[common_idxs_p02]


        #read in samples from ICPC
        @info "Getting waveforms"
        ICPC = read_samples_from_julia(logdir*filename00, dfc_r01, ch = ch)
        
        #declare dictionaries that map old event numbers of CZT to ICPC event numbers
        @info "Mapping CZT events"
        dict1 = Dict{Int32,Int32}([(czt1.evt_no[i], common_idxs_r01[i]) for i in 1:length(czt1.evt_no)])
        dict2 = Dict{Int32,Int32}([(czt2.evt_no[i], common_idxs_r02[i]) for i in 1:length(czt2.evt_no)])
        dict3 = Dict{Int32,Int32}([(common_idxs[i], i) for i in 1:length(common_idxs)])

        #overwrite event numbers in CZT, counting only the coincident ones and adjusting them to the ICPC event numbers
        @info "Overwritting CZT event numbers"
        czt1.evt_no .= map(evtno -> dict3[dict1[evtno]], czt1.evt_no)
        czt2.evt_no .= map(evtno -> dict3[dict2[evtno]], czt2.evt_no)

        #store the sync pulses with old and new timestamps
        @info "Storing sync pulses"
        ICPC_sync1 = round.(Int,ustrip.(u"ns",uconvert.(u"ns",ICPC_raw.evt_t[findall(x -> x == 9, ICPC_raw.chid)]))) .* u"ns"
        ICPC_sync2 = round.(Int,ustrip.(u"ns",uconvert.(u"ns",ICPC_raw.evt_t[findall(x -> x == 10, ICPC_raw.chid)]))) .* u"ns"
        CZT_sync1 = czt_raw1.evt_t[findall(x -> x, czt_raw1.evt_issync)]
        CZT_sync2 = czt_raw2.evt_t[findall(x -> x, czt_raw2.evt_issync)]
        m1 = min(length(ICPC_sync1), length(CZT_sync1))
        m2 = min(length(ICPC_sync2), length(CZT_sync2))
        sync1 = Table(pulse_no = collect(1:m1), ICPC = ICPC_sync1[1:m1], CZT = CZT_sync1[1:m1], CZT_old = CZT_old_sync1[1:m1])
        sync2 = Table(pulse_no = collect(1:m2), ICPC = ICPC_sync2[1:m2], CZT = CZT_sync2[1:m2], CZT_old = CZT_old_sync2[1:m2])

        @info "Writting to file"
        HDF5.h5open(filename, "w") do output
            writedata(output, detname, ICPC)
            writedata(output, "czt", czt1)
            writedata(output, "czt2", czt2)
            writedata(output, "sync", sync1)
            writedata(output, "sync2", sync2)
        end

        #check if it was properly saved
        ICPC_in = HDF5.h5open(filename, "r") do input
            readdata(input, detname)
        end

        czt_in1 = HDF5.h5open(filename, "r") do input
            readdata(input, "czt")
        end

        czt_in2 = HDF5.h5open(filename, "r") do input
            readdata(input, "czt2")
        end

        sync_in1 = HDF5.h5open(filename, "r") do input
            readdata(input, "sync")
        end

        sync_in2 = HDF5.h5open(filename, "r") do input
            readdata(input, "sync2")
        end

        @assert ICPC == ICPC_in
        @assert czt1 == czt_in1
        @assert czt2 == czt_in2
        @assert sync1 == sync_in1
        @assert sync2 == sync_in2


        if delete_src_files
            rm(logdir*filename00)
            rm(logdir*filename01)
            rm(logdir*filename02)
        end

        try
            chmod(filename, 0o774)
        catch
            nothing
        end
        @info "Success!"
        f_s[2] = f_s[2] + 1
    end
end

function filter_and_combine_data_1j(logdir::String, savedir::String; detname = "fadc", ch = 1:5, overwrite = false, delete_src_files = false, f_s = [0,0])

    if logdir[end] != '/'; logdir *= "/"; end
    if savedir[end] != '/'; savedir *= "/"; end

    @assert(isdir(savedir),"$savedir does not exist")
    @assert(isdir(savedir*"../raw_data/"),"$(savedir*"../raw_data/") does not exist")
    @assert(isdir(savedir*"../err_data/"),"$(savedir*"../err_data/") does not exist")

    #filenames = filter(x -> x[end-4:end] == "Z.dat", readdir(logdir))
    #filenames = filter(x -> endswith(x, "Z.dat"), readdir(logdir))

    filenames = sort(filter(x -> endswith(x, "Z.lh5"), readdir(logdir)), by = x -> match(r"T\d{6}Z", x).match[2:end-1])

    for filename00 in filenames

        #save to
        filename = replace(filename00, "-ICPC" => "")
        filename = savedir*replace(filename, ".lh5" => "-filtered.h5")

        if !overwrite && filename in savedir.*readdir(savedir);
            @info("File already exists. Skipping...")
            continue;
        end

        if startswith(filename00, "bkg")
            mv(logdir*filename00, savedir*"../raw_data/"*filename00, force=true)
            try
                rm(logdir*filename01)
            catch
                nothing
            end
            continue;
        end

        filename01 = replace(filename00, "ICPC" => "CZT1")
        filename01 = replace(filename01, ".lh5" => ".h5")

        if !in(filename01, readdir(logdir));
            @warn("CZT file does not exist. Moving file to ../err_data")
            mv(logdir*filename00, savedir*"../err_data/"*filename00, force=true)
            open(savedir*"../err_data/filter_logs.txt", "a") do io
                write(io, "$(now())\t$filename00\tCZT file does not exist\n");
            end
            continue;
        end


        println()
        @info "Filtering $filename00"

        #read in data
        @info "Reading in data"
        ICPC_raw = read_data_from_julia(logdir*filename00, ch = first(ch), sync = [9])
        #check_results(ICPC_raw)

        czt_raw1 = HDF5.h5open(logdir*filename01, "r") do input
            readdata(input, "data_raw")
        end

        CZT_old_sync1 = czt_raw1.evt_t[czt_raw1.evt_issync]
        #=
        events = (dut = ICPC_raw, cam = czt_raw)
        ICPC_raw = nothing
        czt_raw = nothing
        =#

        #align timestamps in CZT data
        fit_went_well = [true]
        @info "Correcting timestamps"
        czt_corr1 = new_correct_time_to_struck!(ICPC_raw, czt_raw1, channel = 9, fit_went_well = fit_went_well)

        if fit_went_well[1] == false
            @warn "Sync fit failed. Moving file and associated CZT file to ../err_data"
            mv(logdir*filename00, savedir*"../err_data/"*filename00, force=true)
            mv(logdir*filename01, savedir*"../err_data/"*filename01, force=true)
            f_s[1] = f_s[1] + 1
            open(savedir*"../err_data/filter_logs.txt", "a") do io
                write(io, "$(now())\t$filename00\tSync fit failed\n");
            end
            continue
        end

        # Find time coincident events in BEGe and CZT1
        @info "Finding common events"
        df_rege = ICPC_raw[findall(x -> x == first(ch), ICPC_raw.chid)]
        df_czt1 = czt_corr1[findall(x -> !x, czt_corr1.evt_issync)]; czt_corr1 = nothing
        
        common_idxs_r01, common_idxs_p01 = my_new_find_common_events((df_rege, df_czt1), 5e-5u"s")
        
        common_idxs = unique(sort(common_idxs_r01))

        #save coincident events
        dfc_r01 = df_rege[common_idxs]
        czt1 = df_czt1[common_idxs_p01]


        #read in samples from ICPC
        @info "Getting waveforms"
        ICPC = read_samples_from_julia(logdir*filename00, dfc_r01; ch, sync = [9])
        
        #declare dictionaries that map old event numbers of CZT to ICPC event numbers
        @info "Mapping CZT events"
        dict1 = Dict{Int32,Int32}([(czt1.evt_no[i], common_idxs_r01[i]) for i in 1:length(czt1.evt_no)])
        
        dict3 = Dict{Int32,Int32}([(common_idxs[i], i) for i in 1:length(common_idxs)])

        #overwrite event numbers in CZT, counting only the coincident ones and adjusting them to the ICPC event numbers
        @info "Overwritting CZT event numbers"
        czt1.evt_no .= map(evtno -> dict3[dict1[evtno]], czt1.evt_no)

        #store the sync pulses with old and new timestamps
        @info "Storing sync pulses"
        ICPC_sync1 = round.(Int,ustrip.(u"ns",uconvert.(u"ns",ICPC_raw.evt_t[findall(x -> x == 9, ICPC_raw.chid)]))) .* u"ns"
        
        CZT_sync1 = czt_raw1.evt_t[findall(x -> x, czt_raw1.evt_issync)]
        
        m1 = min(length(ICPC_sync1), length(CZT_sync1))
        
        sync1 = Table(pulse_no = collect(1:m1), ICPC = ICPC_sync1[1:m1], CZT = CZT_sync1[1:m1], CZT_old = CZT_old_sync1[1:m1])

        @info "Writting to file"
        HDF5.h5open(filename, "w") do output
            writedata(output, detname, ICPC)
            writedata(output, "czt", czt1)
            writedata(output, "sync", sync1)
        end

        #check if it was properly saved
        ICPC_in = HDF5.h5open(filename, "r") do input
            readdata(input, detname)
        end

        czt_in1 = HDF5.h5open(filename, "r") do input
            readdata(input, "czt")
        end


        sync_in1 = HDF5.h5open(filename, "r") do input
            readdata(input, "sync")
        end

        @assert ICPC == ICPC_in
        @assert czt1 == czt_in1
        @assert sync1 == sync_in1


        if delete_src_files
            rm(logdir*filename00)
            rm(logdir*filename01)
        else
            mv(logdir*filename00, savedir*"../raw_data/"*filename00)
			mv(logdir*filename01, savedir*"../raw_data/"*filename01)
        end

        try
            chmod(filename, 0o774)
        catch
            nothing
        end
       @info "Success!"
       f_s[2] = f_s[2] + 1
    end
end

function filter_and_combine_data_1czt(file; ch = 1:5, delete_src_files = false)
    idxd = findlast("/", file)
    dir = isnothing(idxd) ? "" : file[1:idxd[1]]
    filename00 = isnothing(idxd) ? file : file[idxd[1]+1:end]
    #save to
    filename = replace(filename00, "-ICPC" => "")
    filename = replace(filename, ".lh5" => "-filtered.h5")

    filename01 = replace(filename00, "ICPC" => "CZT1")
    filename01 = replace(filename01, ".lh5" => ".h5")

    @info "Filtering $filename00"

    @assert !startswith(filename00, "bkg") "bkg file. File not filtered."

    #read in data
    @info "Reading in data"
    ICPC_raw = read_data_from_julia(dir*filename00, ch = first(ch), sync = [9])
    #check_results(ICPC_raw)

    czt_raw1 = HDF5.h5open(dir*filename01, "r") do input
        readdata(input, "data_raw")
    end

    CZT_old_sync1 = czt_raw1.evt_t[czt_raw1.evt_issync]
    #=
    events = (dut = ICPC_raw, cam = czt_raw)
    ICPC_raw = nothing
    czt_raw = nothing
    =#

    #align timestamps in CZT data
    fit_went_well = [true]
    @info "Correcting timestamps"
    czt_corr1 = new_correct_time_to_struck!(ICPC_raw, czt_raw1, channel = 9, fit_went_well = fit_went_well)
    
    @assert fit_went_well[1] "Timestamp fit fail. File not filtered."

    # Find time coincident events in BEGe and CZT1
    @info "Finding common events"
    df_rege = ICPC_raw[findall(x -> x == first(ch), ICPC_raw.chid)]
    df_czt1 = czt_corr1[findall(x -> !x, czt_corr1.evt_issync)]; czt_corr1 = nothing
    
    common_idxs_r01, common_idxs_p01 = my_new_find_common_events((df_rege, df_czt1), 5e-5u"s")
    
    common_idxs = unique(sort(common_idxs_r01))

    #save coincident events
    dfc_r01 = df_rege[common_idxs]
    czt1 = df_czt1[common_idxs_p01]


    #read in samples from ICPC
    @info "Getting waveforms"
    ICPC = read_samples_from_julia(dir*filename00, dfc_r01; ch)
    
    #declare dictionaries that map old event numbers of CZT to ICPC event numbers
    @info "Mapping CZT events"
    dict1 = Dict{Int32,Int32}([(czt1.evt_no[i], common_idxs_r01[i]) for i in 1:length(czt1.evt_no)])
    
    dict3 = Dict{Int32,Int32}([(common_idxs[i], i) for i in 1:length(common_idxs)])

    #overwrite event numbers in CZT, counting only the coincident ones and adjusting them to the ICPC event numbers
    @info "Overwritting CZT event numbers"
    czt1.evt_no .= map(evtno -> dict3[dict1[evtno]], czt1.evt_no)

    #store the sync pulses with old and new timestamps
    @info "Storing sync pulses"
    ICPC_sync1 = round.(Int,ustrip.(u"ns",uconvert.(u"ns",ICPC_raw.evt_t[findall(x -> x == 9, ICPC_raw.chid)]))) .* u"ns"
    
    CZT_sync1 = czt_raw1.evt_t[findall(x -> x, czt_raw1.evt_issync)]
    
    m1 = min(length(ICPC_sync1), length(CZT_sync1))
    
    sync1 = Table(pulse_no = collect(1:m1), ICPC = ICPC_sync1[1:m1], CZT = CZT_sync1[1:m1], CZT_old = CZT_old_sync1[1:m1])

    @info "Writting to file"
    HDF5.h5open(dir*filename, "w") do output
        writedata(output, "ICPC", ICPC)
        writedata(output, "czt", czt1)
        writedata(output, "sync", sync1)
    end

    #check if it was properly saved
    ICPC_in = HDF5.h5open(dir*filename, "r") do input
        readdata(input, "ICPC")
    end

    czt_in1 = HDF5.h5open(dir*filename, "r") do input
        readdata(input, "czt")
    end


    sync_in1 = HDF5.h5open(dir*filename, "r") do input
        readdata(input, "sync")
    end

    @assert ICPC == ICPC_in
    @assert czt1 == czt_in1
    @assert sync1 == sync_in1


    if delete_src_files
        rm(dir*filename00)
        rm(dir*filename01)
    end

    try
        chmod(dir*filename, 0o774)
    catch
        nothing
    end
    @info "Success!"
end

#=
function filter_and_combine_data_2czts(filename00; overwrite = false, delete_src_files = false)

    @assert(isdir("../raw_data/"), "../raw_data/ does not exist")

    #save to
    filename = replace(filename00, "-ICPC" => "")
    filename = replace(filename, ".lh5" => "-filtered.h5")

    if !overwrite && filename in readdir();
        @info("File already exists. Skipping.")
        return nothing
    end

    filename01 = replace(filename00, "ICPC" => "CZT1")
    filename01 = replace(filename01, ".lh5" => ".h5")

    filename02 = replace(filename00, "ICPC" => "CZT2")
    filename02 = replace(filename02, ".lh5" => ".h5")

    @info "Filtering $filename00"

    if startswith(filename00, "bkg")
        mv(filename00, "../raw_data/"*filename00, force=true)
        try
            rm(filename01, force = true)
        catch
            nothing
        end
        return nothing
    end

    #read in data
    @info "Reading in data"
    ICPC_raw = read_data_from_julia(filename00, ch = [16], sync = [9,10])
    #check_results(ICPC_raw)

    czt_raw1 = HDF5.h5open(filename01, "r") do input
        readdata(input, "data_raw")
    end

    czt_raw2 = HDF5.h5open(filename02, "r") do input
        readdata(input, "data_raw")
    end

    CZT_old_sync1 = czt_raw1.evt_t[czt_raw1.evt_issync]
    CZT_old_sync2 = czt_raw2.evt_t[czt_raw2.evt_issync]
    #=
    events = (dut = ICPC_raw, cam = czt_raw)
    ICPC_raw = nothing
    czt_raw = nothing
    =#

    #align timestamps in CZT data
    fit_went_well = [true]
    @info "Correcting timestamps"
    czt_corr1 = new_correct_time_to_struck!(ICPC_raw, czt_raw1, channel = 9, fit_went_well = fit_went_well)
    czt_corr2 = new_correct_time_to_struck!(ICPC_raw, czt_raw2, channel = 10, fit_went_well = fit_went_well)

    if fit_went_well[1] == false
        @warn "File not filtered. Moving file and associated CZT file to ../raw_data"
        mv(filename00, "../raw_data/"*filename00, force=true)
        mv(filename01, "../raw_data/"*filename01, force=true)
        mv(filename02, "../raw_data/"*filename02, force=true)
        return nothing
    end

    # Find time coincident events in BEGe and CZT1
    @info "Finding common events"
    df_rege = ICPC_raw[findall(x -> x == 16, ICPC_raw.chid)]
    df_czt1 = czt_corr1[findall(x -> !x, czt_corr1.evt_issync)]; czt_corr1 = nothing
    df_czt2 = czt_corr2[findall(x -> !x, czt_corr2.evt_issync)]; czt_corr2 = nothing
    common_idxs_r01, common_idxs_p01 = my_new_find_common_events((df_rege, df_czt1), 5e-5u"s")
    common_idxs_r02, common_idxs_p02 = my_new_find_common_events((df_rege, df_czt2), 5e-5u"s")
    common_idxs = unique(sort(vcat(common_idxs_r01, common_idxs_r02)))

    #save coincident events
    dfc_r01 = df_rege[common_idxs]
    czt1 = df_czt1[common_idxs_p01]
    czt2 = df_czt2[common_idxs_p02]


    #read in samples from ICPC
    @info "Getting waveforms"
    ICPC = read_samples_from_julia(filename00, dfc_r01)
    
    #declare dictionaries that map old event numbers of CZT to ICPC event numbers
    @info "Mapping CZT events"
    dict1 = Dict{Int32,Int32}([(czt1.evt_no[i], common_idxs_r01[i]) for i in 1:length(czt1.evt_no)])
    dict2 = Dict{Int32,Int32}([(czt2.evt_no[i], common_idxs_r02[i]) for i in 1:length(czt2.evt_no)])
    dict3 = Dict{Int32,Int32}([(common_idxs[i], i) for i in 1:length(common_idxs)])

    #overwrite event numbers in CZT, counting only the coincident ones and adjusting them to the ICPC event numbers
    @info "Overwritting CZT event numbers"
    czt1.evt_no .= map(evtno -> dict3[dict1[evtno]], czt1.evt_no)
    czt2.evt_no .= map(evtno -> dict3[dict2[evtno]], czt2.evt_no)

    #store the sync pulses with old and new timestamps
    @info "Storing sync pulses"
    ICPC_sync1 = round.(Int,ustrip.(u"ns",uconvert.(u"ns",ICPC_raw.evt_t[findall(x -> x == 9, ICPC_raw.chid)]))) .* u"ns"
    ICPC_sync2 = round.(Int,ustrip.(u"ns",uconvert.(u"ns",ICPC_raw.evt_t[findall(x -> x == 10, ICPC_raw.chid)]))) .* u"ns"
    CZT_sync1 = czt_raw1.evt_t[findall(x -> x, czt_raw1.evt_issync)]
    CZT_sync2 = czt_raw2.evt_t[findall(x -> x, czt_raw2.evt_issync)]
    m1 = min(length(ICPC_sync1), length(CZT_sync1))
    m2 = min(length(ICPC_sync2), length(CZT_sync2))
    sync1 = Table(pulse_no = collect(1:m1), ICPC = ICPC_sync1[1:m1], CZT = CZT_sync1[1:m1], CZT_old = CZT_old_sync1[1:m1])
    sync2 = Table(pulse_no = collect(1:m2), ICPC = ICPC_sync2[1:m2], CZT = CZT_sync2[1:m2], CZT_old = CZT_old_sync2[1:m2])

    @info "Writting to file"
    HDF5.h5open(filename, "w") do output
        writedata(output, "ICPC", ICPC)
        writedata(output, "czt", czt1)
        writedata(output, "czt2", czt2)
        writedata(output, "sync", sync1)
        writedata(output, "sync2", sync2)
    end

    #check if it was properly saved
    ICPC_in = HDF5.h5open(filename, "r") do input
        readdata(input, "ICPC")
    end

    czt_in1 = HDF5.h5open(filename, "r") do input
        readdata(input, "czt")
    end

    czt_in2 = HDF5.h5open(filename, "r") do input
        readdata(input, "czt2")
    end

    sync_in1 = HDF5.h5open(filename, "r") do input
        readdata(input, "sync")
    end

    sync_in2 = HDF5.h5open(filename, "r") do input
        readdata(input, "sync2")
    end

    @assert ICPC == ICPC_in
    @assert czt1 == czt_in1
    @assert czt2 == czt_in2
    @assert sync1 == sync_in1
    @assert sync2 == sync_in2


    if delete_src_files
        rm(filename00)
        rm(filename01)
        rm(filename02)
    end

    try
        chmod(filename, 0o774)
    catch
        nothing
    end
    @info "Success!"
end
=#
