#!/bin/bash
#=
export JULIA_PROJECT=$(dirname $(dirname $(readlink -e "${BASH_SOURCE[0]}")))
exec julia --color=yes --startup-file=no "${BASH_SOURCE[0]}" "$@"
=#

if length(ARGS) < 2
    error("usage: $(PROGRAM_FILE) OUTFILE INFILE1 [INFILE2 [...]]")
else
    using UVH5Splicer
    outfile = popfirst!(ARGS)
    uvh5_splice(outfile, ARGS)
end
