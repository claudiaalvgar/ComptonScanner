using LegendHDF5IO
using LegendHDF5IO: readdata, writedata
using Unitful
using TypedTables
using HDF5
using ProgressMeter

function my_new_find_common_events(tables::Tuple{Any,Any}, delta_t::Number)
    t = (tables[1].evt_t, tables[2].evt_t)
    sel = Vector{Int}(), Vector{Int}()

    idxs = (eachindex(t[1]), eachindex(t[2]))
    i = map(firstindex, idxs)
    i = (i[1] + 1, i[2] + 1)
    i_max = map(lastindex, idxs)

    while i[1] < i_max[1] && i[2] < i_max[2]
        t1 = t[1][i[1]]
        t2 = t[2][i[2]]

        if t1 <= t2
            #if the difference is within the coincidence window:
            if abs(t1 - t2) < delta_t
                # check if the next one is better: save if next one is worse and skip else
                if abs(t[1][i[1] + 1] - t2) > abs(t1 - t2) && abs(t1 - t[2][i[2] - 1]) > abs(t1 - t2)
                    push!(sel[1], i[1])
                    push!(sel[2], i[2])
                    if t[1][i[1] + 1] < t2
                        i = (i[1] + 2, i[2])
                    else
                        i = (i[1] + 1, i[2] + 1)
                    end
                else
                    i = (i[1] + 1, i[2])
                end
            else
                i = (i[1] + 1, i[2])
            end
        else
            #if the difference is within the coincidence window:
            if abs(t1 - t2) < delta_t
                # check if the next one is better: save if next one is worse and skip else
                if abs(t1 - t[2][i[2] + 1]) > abs(t1 - t2) && abs(t[1][i[1] - 1] - t2) > abs(t1 - t2)
                    push!(sel[1], i[1])
                    push!(sel[2], i[2])
                    if t[2][i[2] + 1] < t1
                        i = (i[1], i[2] + 2)
                    else
                        i = (i[1] + 1, i[2] + 1)
                    end
                else
                     i = (i[1], i[2] + 1)
                end
            else
                i = (i[1], i[2] + 1)
            end
        end
    end
    sel
end

datadir = joinpath(pwd(), "")
files = joinpath.(datadir, filter(x -> endswith(x, "filtered.h5"), readdir(datadir)))
@showprogress for f in files
    h = LHDataStore(f)
    if h["segBEGe/evt_no"][:] == sort(unique(vcat(h["czt/evt_no"], h["czt2/evt_no"])))
        nothing
    else
        @info f
        h = LHDataStore(f);

        ICPC_raw = h["segBEGe"][:]
        czt_corr1 = h["czt"][:]
        czt_corr2 = h["czt2"][:]
        sync1 = h["sync"][:]
        sync2 = h["sync2"][:]
        ;

        # reset event numbers and add an empty event at time 0ns 
        ICPC_raw = Table((
            evt_no = vcat(Int32(0), Int32.(eachindex(ICPC_raw))),
            chid = vcat(Int32(1), ICPC_raw.chid),
            evt_t = vcat(Int64(0)u"ns", ICPC_raw.evt_t),
            DAQ_energy = ICPC_raw.DAQ_energy[vcat(1, 1:end)],
            samples = ICPC_raw.samples[vcat(1, 1:end)]
        ))
        
        # reset event numbers and add 
        czt_corr1.evt_no .= eachindex(czt_corr1)
        czt_corr2.evt_no .= eachindex(czt_corr2)
        
        df_rege = ICPC_raw[findall(x -> x == 1, ICPC_raw.chid)]
        df_czt1 = czt_corr1[findall(x -> !x, czt_corr1.evt_issync)]
        df_czt2 = czt_corr2[findall(x -> !x, czt_corr2.evt_issync)]
        common_idxs_r01, common_idxs_p01 = my_new_find_common_events((df_rege, df_czt1), 5e-5u"s")
        common_idxs_r02, common_idxs_p02 = my_new_find_common_events((df_rege, df_czt2), 5e-5u"s")
        common_idxs = unique(sort(vcat(common_idxs_r01, common_idxs_r02)))
        
        #save coincident events
        ICPC = df_rege[common_idxs]
        czt1 = df_czt1[common_idxs_p01]
        czt2 = df_czt2[common_idxs_p02]
        
        #declare dictionaries that map old event numbers of CZT to ICPC event numbers
        @info "Mapping CZT events"
        dict1 = Dict{Int32,Int32}([(czt1.evt_no[i], common_idxs_r01[i]) for i in 1:length(czt1.evt_no)])
        dict2 = Dict{Int32,Int32}([(czt2.evt_no[i], common_idxs_r02[i]) for i in 1:length(czt2.evt_no)])
        dict3 = Dict{Int32,Int32}([(common_idxs[i], i) for i in 1:length(common_idxs)])

        # overwrite event numbers in CZT, counting only the coincident ones and adjusting them to the ICPC event numbers
        @info "Overwritting CZT event numbers"
        ICPC.evt_no .= eachindex(ICPC)
        czt1.evt_no .= map(evtno -> dict3[dict1[evtno]], czt1.evt_no)
        czt2.evt_no .= map(evtno -> dict3[dict2[evtno]], czt2.evt_no)
        
	@assert ICPC.evt_no == sort(unique(vcat(czt1.evt_no, czt2.evt_no))) "Error still persists"

        mv(f, f*"_old")
        
        @info "Writting to file"
        HDF5.h5open(f, "w") do output
            writedata(output, "segBEGe", ICPC)
            writedata(output, "czt", czt1)
            writedata(output, "czt2", czt2)
            writedata(output, "sync", sync1)
            writedata(output, "sync2", sync2)
        end

        #check if it was properly saved
        ICPC_in = HDF5.h5open(f, "r") do input
            readdata(input, "segBEGe")
        end

        czt_in1 = HDF5.h5open(f, "r") do input
            readdata(input, "czt")
        end

        czt_in2 = HDF5.h5open(f, "r") do input
            readdata(input, "czt2")
        end

        sync_in1 = HDF5.h5open(f, "r") do input
            readdata(input, "sync")
        end

        sync_in2 = HDF5.h5open(f, "r") do input
            readdata(input, "sync2")
        end

        @assert ICPC == ICPC_in
        @assert czt1 == czt_in1
        @assert czt2 == czt_in2
        @assert sync1 == sync_in1
        @assert sync2 == sync_in2
	
	chmod(f, 0o754)
    end
    close(h)
end
