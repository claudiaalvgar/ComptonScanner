using ArraysOfArrays
using HDF5
using LegendHDF5IO: readdata, writedata
using Statistics
using TypedTables
using Unitful
using LsqFit
using ProgressMeter
using Dates


"""
    sortevents(unsorted::Table; ch = [16], sync = [9,10])::Table

Sorts an ´unsorted´ ´Table´ (initially sorted by channel id) bufferwise by timestamp.
Each physical event should have an entry in each channel in ´ch´ with the same timestamp.
If some waveforms in any of the channels of ´ch´ are missing, the whole event is discarded.
Sync pulse events in the channels ´sync´ will not be discarded and appended at the end
of each sorted buffer dataset.

"""
#=
function sortevents(unsorted::Table; ch = [16], sync = [9,10])::Table
    #println(unsorted)
    cidx = Int32[]
    first = 1

    #sort, group and discard events for one buffer dataset at a time
    for b in unique(unsorted.bufferno)

        #find the index at which the buffer number increases
        #(this gives the first index after end of buffer if the events are sorted by buffer number)
        next = (b == maximum(unsorted.bufferno)) ? length(unsorted) + 1 : findfirst(unsorted.bufferno[first:end] .> b) + first - 1

        #choose events in that buffer
        chunk = unsorted[first:next-1]
        chid = chunk.channel
        evt_t = chunk.timestamp
        syncidx = findall(c -> c in sync, chid)
        dataidx = findall(c -> c in ch, chid)
        #sort the row numbers by their corresponding event time, and each event with same event time by channel id
        dataidx = sort(dataidx, lt = (a,b) -> evt_t[a] < evt_t[b] || (evt_t[a] == evt_t[b] && chid[a] < chid[b]))
        #cut the array at a multiple of length(ch), as anything more would hint to incomplete set of events
        dataidx = dataidx[1:end-end%length(ch)]

        #and each of the channels counts their event number separately, waveforms from the same events should have
        #the same event number and it should be only increasing. If a waveform is missing in at least one of the channels,
        #it will have a lower event number than the others in the next event. So, if at some point the DAQ event number
        #decreases, some waveforms in the event are missing and the event should be discarded
        
        if length(ch) > 1 && minimum(diff(chunk.daqevtno[dataidx])) < 0
            sorted_t = evt_t[dataidx]
            offset = 0
            nfails = 0
            failed = Int32[]
            for i in 0:Int(length(dataidx)/length(ch)-1)
                #check whether the first event timestamp in a group of length(ch) events matched the mean of the rest
                #if not, this event is incomplete and should be discarded (corresponding event idx will be saved in failed)
                if sorted_t[length(ch)*(i-nfails)+offset+1] != mean(sorted_t[length(ch)*(i-nfails)+offset.+collect(ch)])
                    l = findlast(sorted_t[length(ch)*(i-nfails).+collect(ch).+offset] .== sorted_t[length(ch)*(i-nfails)+1+offset])
                    failed = vcat(failed, Int32.(length(ch)*(i-nfails)+1+offset:length(ch)*(i-nfails)+l+offset))
                    offset += l
                    nfails += 1
                end
            end
            dataidx = dataidx[filter(i -> !(i in failed), 1:length(dataidx)-length(ch)*nfails+offset)]
        end

        #append data indices and sync indices to the list of indices and repeat with the next buffer
        cidx = vcat(cidx, dataidx.+first.-1, syncidx.+first.-1)
        first = next
    end
    #sort the unsorted Table with the sorted event idx obtained in this routine
    return unsorted[cidx]
end
=#

function sortevents(data_in::Table; ch = 1:5, sync = [9,10])::Table
    evt_t = data_in.timestamp[:]
    chid = data_in.channel[:]
    dataidx = findall(c -> c in ch, chid)
    syncidx = findall(c -> c in sync, chid)
    sort!(dataidx, lt = (a,b) -> evt_t[a] < evt_t[b] || (evt_t[a] == evt_t[b] && chid[a] < chid[b]))
    i = 1
    N = length(dataidx)
    while i < N - length(ch)
        if all(chid[dataidx[i:i+length(ch)-1]] .== ch) && all(evt_t[dataidx[i]] .== evt_t[dataidx[i:i+length(ch)-1]])
            i += length(ch)
        else
            #@info evt_t[dataidx[i:i+length(ch)-1]]
            di = findfirst(evt_t[dataidx[i:i+length(ch)-1]] .> evt_t[dataidx[i]])
            #@warn "idx : $(di), i: $i, deleting $(length(i:i+di-2)) entries"
            deleteat!(dataidx, i:i+di-2)
            N = length(dataidx)
        end
    end
    t = data_in[dataidx[1:i-1]] 

    # Check that the Table fulfills the wanted requirements
    @assert all(t.channel .== (eachindex(t) .- 1) .% length(ch) .+ 1)
    t.daqevtno .= t.daqevtno[length(ch) .* div.(eachindex(t) .- 1, length(ch)) .+ 1]
    @assert all([all(t.timestamp[i:i+length(ch)-1] .== t.timestamp[i]) for i in 1:length(ch):length(t)])
    @assert all([all(t.daqevtno[i:i+length(ch)-1] .== t.daqevtno[i]) for i in 1:length(ch):length(t)])

    vcat(t, data_in[syncidx])
end




"""
    check_results(data_in::Table; ch = [16])

For debugging: Check whether the output Table after sorting and discarding fulfills all requirements.
Throws an ´AssertionError´ if events are incomplete, misplaced or not at the same time.

"""
function check_results(data_in::Table; ch = 1:5)
    data = data_in[findall(c -> c in ch, data_in.chid)]
    @assert length(data)%length(ch) == 0 "At least one event is not complete."
    for s in 1:length(ch)
        @assert prod(data.chid[s:length(ch):end] .== s) "An event with channel id $(s) is misplaced"
    end
    for i in 1:Int(length(data)/length(ch))
        @assert mean(data.evt_t[length(ch)*(i-1).+collect(1:length(ch))]) == data.evt_t[length(ch)*i] "In one event, at least one channel has a different timestamp than the others."
    end
end




"""
    check_file_format(filename::String)

Checks whether the file is saved in the right format and contains the field used in the upcoming processing.
Throws an ´AssertionError´ if the file is not in the right format.

"""
function check_file_format(filename::String)
    @assert isfile(filename) "Given file does not exist."
    @assert endswith(filename, ".lh5") "Given file is not saved as .lh5 file."
    @assert h5open(filename, "r") do h5f "1" in keys(h5f) end "Given file does not have the data saved in '1'."
end


function convert_time(time::Array{Int,1}, Δt = 4u"ns")::Array{typeof(4u"ns"),1}
    return time .* Δt
end


"""
    read_data_from_julia(filename::String; ch = [16], sync = [9,10])::Table

Reads a ´.lh5´ file taken with the STRUCK DAQ implementation with Julia, sorts them by timestamp,
discards all incomplete events and  returns a ´Table´ with the channel id, the event timestamp,
the DAQ energy and the buffer number for each event and each channel.

"""
# function read_data_from_julia(filename::String; ch = [16], sync = [9,10])::Table
#
#     #check whether the file is in the right format
#     check_file_format(filename)
#
#     #read in part of the dataset, skip the samples for increasing the sorting performance
#     data_in = h5open(filename, "r") do h5f
#         Table(
#             daqevtno = readdata(h5f, "raw/daqevtno"),
#             bufferno = readdata(h5f, "raw/bufferno"),
#             channel = readdata(h5f, "raw/channel"),
#             timestamp = readdata(h5f, "raw/timestamp"),
#             energy = readdata(h5f, "raw/energy")
#         )
#     end
#
#     #sort the events by timestamp and discard incomplete events
#     sorted = sortevents(data_in, ch = ch, sync = sync)
#
#     #return a Table of sorted and grouped events for further analysis
#     return Table(
#         chid = sorted.channel,
#         evt_t = convert_time(sorted.timestamp),
#         DAQ_energy = sorted.energy,
#         buffer = sorted.bufferno
#     )
# end

function read_data_from_julia(filename::String; ch = 1:5, sync = [9,10])::Table

    #check whether the file is in the right format
    check_file_format(filename)

    #read in part of the dataset, skip the samples for increasing the sorting performance

    data_in = h5open(filename, "r") do h5f
        groups= sort( keys(h5f), by = x -> parse(Float64, x))
        _data = Table(
            daqevtno = readdata(h5f, groups[1]*"/daqevtno"),
            bufferno = readdata(h5f, groups[1]*"/bufferno"),
            channel = readdata(h5f, groups[1]*"/channel"),
            timestamp = readdata(h5f, groups[1]*"/timestamp"),
            energy = readdata(h5f, groups[1]*"/energy")
        )
        for g in groups[2:end] append!(_data, Table(
            daqevtno = readdata(h5f, g*"/daqevtno"),
            bufferno = readdata(h5f, g*"/bufferno"),
            channel = readdata(h5f, g*"/channel"),
            timestamp = readdata(h5f, g*"/timestamp"),
            energy = readdata(h5f, g*"/energy")
        ))
        end
        _data
    end

    #sort the events by timestamp and discard incomplete events
    sorted = sortevents(data_in, ch = ch, sync = sync)

    #return a Table of sorted and grouped events for further analysis
    return Table(
        chid = sorted.channel,
        evt_t = convert_time(sorted.timestamp),
        DAQ_energy = sorted.energy,
        buffer = sorted.bufferno
    )
end


"""
    read_samples_from_julia(filename::String, coincident_times::Table; ch = [16], sync = [9,10])::Table

Reads a ´.lh5´ file taken with the STRUCK DAQ implementation with Julia, and keeps only the events
with times provided by the Table ´coincident_times´ that should have at least the two columns
´evt_t´ with event timestamps and ´buffer´ with the buffer number. It sorts the remaining events by
timestamp, discards all incomplete events and returns a ´Table´ with the event number, channel id,
the event timestamp, the DAQ energy and the waveform samples for each event and each channel.

"""
function read_samples_from_julia(filename::String, coincident_times::Table; ch = 1:5, sync = [9,10])::Table

    #check whether the file is in the right format
    check_file_format(filename)

    #read in the whole dataset
    # data_in = h5open(filename, "r") do h5f readdata(h5f, "raw") end

    groups =  sort( h5open(filename, "r") do h5f keys(h5f) end, by = x -> parse(Float64, x) )
    data_in = h5open(filename, "r") do h5f readdata(h5f, groups[1]) end
    @showprogress for g in groups[2:end] append!(data_in, h5open(filename, "r") do h5f readdata(h5f, g) end) end

    #for each buffer: find all row numbers with timestamps given in coincident_times
    f = 0
    cidx = Int32[]

    for b in unique(data_in.bufferno)
        buffer = findall(data_in.bufferno .== b)
        reftimes = coincident_times.evt_t[findall(coincident_times.buffer .== b)]
        tidx = findall(i -> i in reftimes, convert_time(data_in.timestamp[buffer]))
        cidx = vcat(cidx, f.+tidx)
        f += length(buffer)
    end

    #reduce the Table to only these events and sort them by timestamp
    sorted = sortevents(data_in[cidx], ch = ch, sync = sync)

    #return a Table of sorted and grouped events for further analysis
    return Table(
        evt_no = round.(Int32,collect(1:length(sorted))./length(ch), RoundUp),
        chid = sorted.channel,
        evt_t = convert_time(sorted.timestamp),
        DAQ_energy = sorted.energy,
        samples = VectorOfArrays(Array{Int16,1}.(sorted.samples))
    )

end



"""
    read_all_from_julia(filename::String; ch = [16], sync = [9,10])::Table

Reads a ´.lh5´ file taken with the STRUCK DAQ implementation with Julia, sorts them by timestamp,
discards all incomplete events and returns a ´Table´ with the event number, channel id, the event timestamp,
the DAQ energy and the waveform samples for each event and each channel.

"""
function read_all_from_julia(filename::String; ch = 1:5, sync = [9,10])::Table

    #check whether the file is in the right format
    check_file_format(filename)

    #read in the whole dataset
    #data_in = h5open(filename, "r") do h5f readdata(h5f, "raw") end

    groups =  sort( h5open(filename, "r") do h5f keys(h5f) end, by = x -> parse(Float64, x) )
    data_in = h5open(filename, "r") do h5f readdata(h5f, groups[1]) end
    for g in groups[2:end] append!(data_in, h5open(filename, "r") do h5f readdata(h5f, g) end) end

    #sort the events by timestamp and discard incomplete events
    sorted = sortevents(data_in, ch = ch, sync = sync)

    #return a Table of sorted and grouped events for further analysis
    return Table(
        evt_no = round.(Int32,collect(1:length(sorted))./length(ch), RoundUp),
        chid = sorted.channel,
        evt_t = convert_time(sorted.timestamp),
        DAQ_energy = sorted.energy,
        samples = VectorOfArrays(Array{Int16,1}.(sorted.samples))
    )
end

function new_correct_time_to_struck!(dut::Table, cam::Table; channel::Integer, core::Integer = 1, fit_went_well::Vector{Bool})

    tstruck = in_ns.(dut.evt_t[dut.chid .== channel])
    tsync = in_ns.(cam.evt_t[cam.evt_issync])
    czt = copy(cam)

    #find all regular sync pulses with distances of (2.00 ± 0.01)s, expected are ≈ 2s.
    idxt = findall(d -> 1.99e9 < d < 2.01e9, diff(tstruck))
    #determine mean Δt for the regular pulses
    meanΔt = mean(diff(tstruck)[idxt])

    #determine all fake pulses (not missing, but triggering on noise)
    falsepulses = []
    while true
        theidx = findfirst(.!isinteger.(round.(diff(tstruck[setdiff(1:end, falsepulses)]) ./ meanΔt, digits = 3)))
        if isnothing(theidx) break end
        push!(falsepulses, theidx+1)
    end

    if length(falsepulses) != 0 @info "Sync pulses in Ge data are missing." end

    #determine the indices to compare to the CZT sync pulses (and make it maximum as long as the number of CZT sync pulses)
    cztidx = Int.(round.((tstruck[setdiff(1:end, falsepulses)] .- tstruck[setdiff(1:end, falsepulses)][1]) ./ meanΔt, digits = 3)) .+ 1
    cztidx = cztidx[cztidx .<= length(tsync)]

    #overwrite tstruck by deleting all fake pulses (and all the ones not captured by the CZT)
    tstruck = tstruck[setdiff(1:length(tstruck), falsepulses)][1:length(cztidx)]

    whichsync = 0
    coincidences = 0
    finalp1 = NaN
    finalp2 = NaN
    c = []

    #We don't know which cam sync pulses correspond to those recorded by the struck. But once we find the first common one, the rest should overlap. 
    #This loop matches different sets of sync pulses to find the one which maximizes coincidences. 
    #Only one should be correct. The others will give just random coincidences. This "i" will be the index of the first real common one. 
    for (i,s) in enumerate(0:10)

        fit_result = curve_fit((x, p) -> p[1] .+ p[2] * x, tsync[s.+cztidx[1:end-s]], tstruck[1:end-s], [Float64(tsync[1]), 1.1])
        fit_p1 = fit_result.param[1]
        fit_p2 = fit_result.param[2]
        czt.evt_t .= round.(Int,(fit_p1 .+ fit_p2 .* in_ns.(cam.evt_t)))*u"ns"
        a,b = my_new_find_common_events((dut[dut.chid .== core], czt[findall(x -> !x, czt.evt_issync)]), 50000u"ns")
        #println(s, " \t", length(a))
        push!(c, length(a))
        if length(a) > coincidences
            @info "Coincidence!"
            whichsync = i
            coincidences = length(a)
            finalp1 = fit_p1
            finalp2 = fit_p2
        end
    end
    #Check if one is indeed significantly above random coincidences
    if (coincidences - mean(c[1:end .!= whichsync]))/std(c[1:end .!= whichsync]) < 10
	    @warn "Fit might not show enough coincidences: $(c[1:end .!= whichsync])"
        fit_went_well[1] = false
    end

    cam.evt_t .= round.(Int,(finalp1 .+ finalp2 .* in_ns.(cam.evt_t)))*u"ns"

    #Clocks in CZT and struck should be very close in pace
    if abs(finalp2 - 1.0) > 0.001
        @info "The fit deviates more than 0.1% from what is expected"
        fit_went_well[1] = false
    end

    cam
end

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

#convenience functions
in_ns(x::Number) = ustrip(uconvert(u"ns", x))
in_μs(x::Number) = ustrip(uconvert(u"μs", x))
in_s(x::Number) = ustrip(uconvert(u"s", x))
in_keV(x::Number) = ustrip(uconvert(u"keV", x))
in_mm(x::Number) = ustrip(uconvert(u"mm", x));
