# UVH5Splicer

Given a list of UVH5 files that contain data from the same observation but cover
different portions of the frequency band, UVH5Splicer will output an HDF5 file
containing virtual and non-virtual datasets such that the output file appears to
contain all the data from the imput UVH5 files in a single UVH5 file.  In order
for this to be viable, the input datasets must be commensurate in multiple ways.

## Commensurate checks

For many of the UVH5 datasets, commensurateness is simply checking for equality.
For example, `Nbls` and most other dimensioning related datasets must have the
same value.  To ensure that the baseline ordering in `visdata` et al. is
commensurate, the `ant_1_array` and `ant_2_array` datasets must be identical
across all input UVH5 files.  The default commensurateness check for datasets is
that they are equal.  Exceptions to this default rule are listed here.

### Frequency

The `freq_array` values will obviously be different across the input files.  The
`freq_array` dataset in the output file will be a concatenation of the
`freq_array` datasets of the input files.   The input `freq_arrays` will appear
in the output `freq_array` in the order in which the input files are given.
Gaps due to "missing" input files are ignored since `freq_array` does not
require a constant frequency step size.  The output file's `Nfreqs` value will
be the sum of the `Nfreqs` values of the input files.  Other `Header` datasets
that are dimensioned by `Nfreqs` will be likewise concatenated.  The complete
list of these datasets is:

- `channel_width`
- `freq_array`

Currently, only datasets with `flex_spw` set to false (0) and `Nspws` equal to 1
are supported and `flex_spw_id_array` is ignored and not copied into the output
file.

### Time

The `Nblts` value in the output file is currently the minimum of the `Nblts`
values across the input data files.  The `time_array` in the output dataset will
be the first `Nblts` elements of the input `time_array` datasets, which must all
be identical.  The `Ntimes` values may vary across the input files.  In the
output file, `Ntimes` is set to the number of unique time values in the output
`time_array`.  Other `Header` datasets that are dimensioned by `Nblts` are
also only required to be commensurate for first output `Nblts` elements:

- `ant_1_array`
- `ant_2_array`
- `integration_time`
- `lst_array`
- `time_array`
- `uvw_array`

A future version may allow for more flexibility in this area (e.g. by using the
maximum of `Nblts` instead).

### Antennas and baselines

Datasets in the input files related to antennas and baselines must all be
identical, except as mentioned above.

### History

The `history` datasets from the input files are not copied to the output file.
Instead, an history dataset is created that contains information about the
`UVH5Splicer` version used to create the spliced output file and a list of the
input files that are spliced in the outut file.

### extra_keywords

Any `extra_keywords` groups in the input files are ignored by the current
implementation since these datasets are not universally defined.

### Visibility data (`visdata`) and friends

The visibility dataset `visdata` will be virtual.  It will have the same `Npols`
dimension as the `visdata` datasets of the input files.  Its `Nblts` dimension
is the minimum `Nblts` value across the input file.  Its `Nfreqs` dimension will
be the sum of the `Nfreqs` values from the input datasets.

## Virtual vs non-virtual

In the output file, all `Header` datasets are non-virtual so as to avoid making
`Header` datasets refer to the corresponding dataset in an arbitrary input file
(e.g. the first one).  Such a dependency would render the output file unusable
if that particular input file were unavailable.  All `Data` datasets in the
output file are virtual and refer to data within the corresponding datasets of
all input files.

### Header dataset selection

The datasets that are created in the output file's `Header` group are the
datasets that are common to all `Header` groups of the input files.  Except for
the exceptions mentioned above, these datasets are checked for equality across
all input files and then copied from the first input file into the output file.
