module UVH5Splicer

export uvh5_splice

using Pkg
using HDF5

#=const=# EQUALITY_EXEMPT_HEADERS = (
    "Nblts",
    "Nfreqs",
    "Ntimes",
    "ant_1_array",
    "ant_2_array",
    "channel_width",
    "flex_spw_id_array",
    "extra_keywords",
    "freq_array",
    "history",
    "integration_time",
    "lst_array",
    "time_array",
    "uvw_array"
)

function all_same(hdrs, name)
    values = getindex.(getindex.(hdrs, name))
    if all(Ref(values[1]) .== values[2:end])
        return true
    end
    @warn "mismatch detected in $name" _module=nothing _file=nothing
    return false
end

"""
    check_commensurate(hdrs, check_names)
 
Check that the datasets listed in `check_names` in the `hdrs` are equal.
Returns an Array of `check_names` datasets that are not equal across all `hdrs`,
which will be empty if all the datasets are equal across all headers.
"""
function check_commensurate(hdrs, check_names)
    oks = all_same.(Ref(hdrs), check_names)
    check_names[.!oks]
end

function splice_datset_by_frequency(h5out, h5ins, name, outdims)
    # Create data type for virtual dataset
    vtype = datatype(h5ins[1][name])
    # Create dataspace for virtual dataset
    vspace = dataspace(outdims) # (Npols, Nfreqsout, Nbltsout)
    # Create dataset creation property list for virtual dataset
    #dcpl = HDF5.h5p_create(HDF5.H5P_DATASET_CREATE)
    dcpl = create_property(HDF5.H5P_DATASET_CREATE)
    # Create source dataspace based on Nfreqs of first dataset
    nfreqin = h5ins[1]["Header/Nfreqs"][]
    sspace = dataspace(outdims[1], nfreqin, outdims[3])
    # Setup hyperslab parameters
    # NB: low level HDF5 functions use 0-based indexing!
    # NB: low level HDF5 functions use C ordering of dimensions!
    voffset = [0, 0, 0] # [blt, freq, pol]
    vstride = [1, 1, 1]
    vcount = [1, 1, 1]

    # Map regions of vspace to regions in source files/datasets
    for h5 in h5ins
        # Ensure source dataspace has proper Nfreqs dimension
        if nfreqin != h5["Header/Nfreqs"][]
            nfreqin = h5["Header/Nfreqs"][]
            close(sspace)
            sspace = dataspace(outdims[1], nfreqin, outdims[3])
        end
        # Select hyperslab in virtual dataspace
        # NB: low level HDF5 functions use 0-based indexing!
        # NB: low level HDF5 functions use C ordering of dimensions!
        vblock = [outdims[3], nfreqin, outdims[1]]
        HDF5.h5s_select_hyperslab(vspace, HDF5.H5S_SELECT_SET,
                                  voffset, vstride, vcount, vblock)
        # Map it!
        HDF5.h5p_set_virtual(dcpl, vspace, HDF5.filename(h5), name, sspace)
        # Adjust voffset
        voffset[2] += nfreqin
    end
    # Close source dataspace
    close(sspace)
    # Since h5s_select_all is not currently availble in HDF5.jl, close and
    # recreate vspace.
    close(vspace)
    vspace = dataspace(outdims) # (Npols, Nfreqsout, Nbltsout)

    # Create virtual dataset
    # TODO Ensure links are created with UTF8 cset encoding?
    HDF5.h5d_create(h5out, name, vtype, vspace,
                    HDF5.DEFAULT_PROPERTIES, dcpl, HDF5.DEFAULT_PROPERTIES)
    
    # Close up
    close(vtype)
    close(vspace)
end

function uvh5_splice(outfile, infiles)
    # Open input files
    h5ins = h5open.(infiles)

    # Get Header groups
    hdrins = getindex.(h5ins, "Header")
    # Get all names from all input headers
    all_names = keys.(hdrins)
    # Get names common to all input headers
    common_names = reduce(intersect, all_names)
    # Reject names in the EQUALITY_EXEMPT_HEADERS list
    copy_names = filter(∉(EQUALITY_EXEMPT_HEADERS), common_names)

    # Check that the must-be-equal datasets are equal
    mismatches = check_commensurate(hdrins, copy_names)
    if !isempty(mismatches)
        error("input datasets $mismatches are not commensurate")
    end

    # Determine the minimum Nblts

    Nbltsout = minimum(getindex.(getindex.(hdrins, "Nblts")))
    # Check 1D arrays dimensioned by Nblts
    for name in ("ant_1_array", "ant_2_array", "integration_time",
                 "lst_array", "time_array")
        vals = getindex.(getindex.(hdrins, name))
        for i = 1:length(vals)
            if vals[1][1:Nbltsout] != vals[i][1:Nbltsout]
                error("input datasets $name are not commensurate")
            end
        end
    end
    # Check 1D arrays dimensioned by Nblts
    vals = getindex.(getindex.(hdrins, "uvw_array"))
    for i = 1:length(vals)
        if vals[1][:, 1:Nbltsout] != vals[i][:, 1:Nbltsout]
            error("input datasets uvw_array are not commensurate")
        end
    end

    # Everything is commensurate!  OK to create output file.
    h5out = h5open(outfile, "w")
    hdrout = create_group(h5out, "Header")

    # Copy the "easy" datasets
    for name in copy_names
        @info "copying $name"
        HDF5.h5o_copy(hdrins[1], name, hdrout, name, HDF5.H5P_DEFAULT, HDF5.H5P_DEFAULT)
    end

    # Copy the Nblts datasets, then adjust to Nbltsout
    # Scalar
    @info "storing Nblts"
    hdrout["Nblts", layout=HDF5.H5D_COMPACT] = Nbltsout
    # 1D
    for name in ("ant_1_array", "ant_2_array", "integration_time",
                 "lst_array", "time_array")
        @info "copying $name and setting dims"
        HDF5.h5o_copy(hdrins[1], name, hdrout, name, HDF5.H5P_DEFAULT, HDF5.H5P_DEFAULT)
        HDF5.set_extent_dims(hdrout[name], (Nbltsout,))
    end
    # 2D
    @info "copying uvw_array and setting dims"
    HDF5.h5o_copy(hdrins[1], "uvw_array", hdrout, "uvw_array", HDF5.H5P_DEFAULT, HDF5.H5P_DEFAULT)
    HDF5.set_extent_dims(hdrout["uvw_array"], (3, Nbltsout))
    # Recompute Ntimes
    time_array_out = hdrout["time_array"][]
    Ntimesout = length(unique(time_array_out))
    @info "storing Ntimes"
    hdrout["Ntimes", layout=HDF5.H5D_COMPACT] = Ntimesout

    # Concatenate frequency datasets
    freq_array_out = reduce(vcat, getindex.(getindex.(hdrins, "freq_array")))
    chan_width_out = reduce(vcat, getindex.(getindex.(hdrins, "channel_width")))
    Nfreqsout = length(freq_array_out)
    @info "storing concatenated freq_array"
    hdrout["freq_array"] = freq_array_out
    @info "storing concatenated channel_width"
    hdrout["channel_width"] = chan_width_out
    @info "storing Nfreqs"
    hdrout["Nfreqs", layout=HDF5.H5D_COMPACT] = Nfreqsout

    # Output history dataset
    toml = Pkg.TOML.parsefile(joinpath(pkgdir(@__MODULE__), "Project.toml"))
    history = reduce((a,b)->"$a\n- $b", HDF5.filename.(h5ins),
                     init="# Created with $(toml["name"]) version $(toml["version"])")

    # This is probably more complicated than it needs to be
    @info "storing history"
    dt = HDF5.create_datatype(HDF5.H5T_STRING, sizeof(history))
    HDF5.h5t_set_strpad(dt, HDF5.H5T_STR_NULLTERM)
    HDF5.h5t_set_cset(dt, HDF5.H5T_CSET_UTF8)
    history_dataset = create_dataset(hdrout, "history", dt, ())
    write_dataset(history_dataset, dt, history)
    close(dt)

    # Create virtual datasets in "Data" group
    dataout = create_group(h5out, "Data")

    # Create dataspace for spliced datasets
    Npols = hdrins[1]["Npols"][]
    for name in ("visdata", "flags", "nsamples")
        @info "splicing $name"
        splice_datset_by_frequency(h5out, h5ins, "/Data/$name", (Npols, Nfreqsout, Nbltsout))
    end

    # Close input files and output file
    close.(h5ins)
    close(h5out)
end

end # module UVH5Splicer
