
# TODO:
# implement Sentinel1SLC{Amplitude/Intensity} support
# test iteration



abstract type Sentinel1 end


"""
	Sentinel1GRD{T <: AbstractFloat}(f::Function, safe_file="safe_file")

safe_file can be either path to `<safe_file>.SAFE` directory or path to `manifest.safe` file.

Defaults to Sentinel1GRD{Float32} if parametric type is not specified.
"""
struct Sentinel1GRD{T <: AbstractFloat} <: Sentinel1
	safe_file::AbstractString
	dataset::ArchGDAL.AbstractDataset
	dtype::DataType

	function Sentinel1GRD{T}(f::Function; safe_file) where T <: Real
		
		ArchGDAL.read(safe_file) do dataset
			S = new(safe_file, dataset, T)
			# do consistency checking of S here.
			f(S)
		end
	end

	# default for the case of no parametric type specification
	Sentinel1GRD(f::Function; safe_file) = Sentinel1GRD{Float32}(f, safe_file=safe_file)
end

"""
	Sentinel1band(f::Function; sentinel1::Sentinel1, band_no::Int64)

An adapter struct around ArchGDAL.AbstractRasterBand. Needed to allow multiple dispatch on
different SAR products.
"""
struct Sentinel1band
	sentinel1::Sentinel1
	band::ArchGDAL.AbstractRasterBand
	band_no::Int64

	function Sentinel1band(f::Function; sentinel1::Sentinel1, band_no::Int64)
		1 ≤ band_no ≤ n_bands(sentinel1) || error("""
			band number: $band_no out of range for $sentinel1.""")

		ArchGDAL.getband(sentinel1.dataset, band_no) do band
			B = new(sentinel1, band, band_no)
			f(B)
		end
	end
end


struct Sen1shape
	n_bands
	n_rows
	n_cols
	function Sen1shape(; n_bands::Int64, n_rows::Int64, n_cols::Int64)
		n_bands > 0 && n_rows > 0 && n_cols > 0 || error(
			"""n_bands, n_cols and n_rows must all be > 0 \
			but have Sen1shape(n_bands:$n_bands, n_rows:$n_rows, n_cols:$n_cols)."""
		)
		new(n_bands, n_rows, n_cols)
	end
end



function Base.print(io::IO, b::Sentinel1band) 
	print(io, """$(typeof(b))($(b.sentinel1), b.band_no)""")
end


function Base.print(io::IO, s::Sentinel1GRD) 
	print(io, "$(typeof(s))(\"$(s.safe_file)\")")
end


function parse_sentinel1_string(safe_file::String)
	d = Dict{String, String}()

	safe_file = Base.Filesystem.splitpath(safe_file)[end]
	safe_file, ext = splitexit(safe_file)
	ext == "SAFE" || error("$safe_file should contain '.SAFE'.")
	fields = split(safe_file, "_")

	length(fields) == 9 || error("number of fields ≠ 9 for $safe_file.")
	(mission_id, beam_mode, bundle1, bundle2, start_time, stop_time, orbit_number, mission_data_take_id, product_id) = fields

	mission_id ∈ ("S1A", "S1B") || error("invalid mission id for $safe_file.")
	beam_mode ∈ ("EW", "IW", "WV")

	length(bundle1) == 4 || error("could not determine product type and resolution class from $safe_file.")
	product_type = bundle1[1:3]
	resolution_class = bundle1[end:end]
	product_type ∈ ("SLC", "GRD", "OCN") || error("invalid product type for $safe_file.")
	resolution_class ∈ ("F", "H", "M") || error("invalid resolution class for $safe_file.")

	length(bundle2) == 4 || error("could not determine processing level, product class and polarisation from $safe_file.")
	processing_level = bundle2[begin:begin]
	product_class = bundle2[2:2]
	polarisation = bundle2[3:end]

	processing_level ∈ ("1", "2")
	product_class ∈ ("S", "A")
	polarisation ∈ ("SV", "SH", "DV", "DH")

	d["mission_id"] 		= mission_id
	d["beam_mode"] 			= beam_mode
	d["product_type"] 		= product_type
	d["resolution_class"] 	= resolution_class
	d["processing_level"] 	= processing_level
	d["product_class"] 		= product_class
	d["polarisation"] 		= polarisation

	d
end



"""
	nbands(s::Sentinel1GRD)

Return number of bands.
"""
function n_bands(s::Sentinel1)
	n = @mock ArchGDAL.nraster(s.dataset)
	n ≠ 0 || error("could not read the number of bands for $s.")
	n
end


"""
	size(s::Sentinel1)

Return size of the rasterbands in the form of a struct with the fields: `(n_bands, n_rows, n_cols)`.
"""
function Base.size(s::Sentinel1)::Sen1shape
	Sen1shape(n_bands=convert(Int64, n_bands(s)),
			  n_rows=convert(Int64, ArchGDAL.height(s.dataset)),
			  n_cols=convert(Int64, ArchGDAL.width(s.dataset)))
end


"""
	pol_from_band(band::Sentinel1band)

Retrieve the polarisation ∈ ("HH", "HV", "VV", "VH") associated with a given 
band.
"""
function polarization(b::Sentinel1band)::String
	
	# metadata is an array of the form [..., "POLARIZATION=<POL>", ...]
	metadata = @mock ArchGDAL.metadata(b.band)
	pol_index = findfirst(x -> occursin("POLARIZATION=", x), metadata)
	pol_index ≠ nothing || error("""
		could not find polarization from metadata for $b.""")

	polarization = split(metadata[pol_index], "=")[end]
	polarization ∈ VALID_POLS || error("""
		invalid polarization: $polarization for $b.""")
	polarization
end


"""
	polarisations(s::Sentinel1)

Retrieve ordered polarisations of all the bands, according to polarisation_sort.
"""
function polarizations(s::Sentinel1)::Vector{String}
	polarizations = String[]
	for band_no in 1:n_bands(s)
		Sentinel1band(sentinel1=s, band_no=band_no) do band
			push!(polarizations, polarization(band))
		end
	end
	sort(polarizations, by=polarization_sort)
end

"""
	band_no(s::Sentinel1; polarization_::String)

Retrieve band number with given polarization or throw error.
"""
function band_no(s::Sentinel1; polarization_::String)::Int64
	polarization_ ∈ VALID_POLS || error("polarization: $polarization_ is invalid.")

	band_no = findfirst(1:n_bands(s)) do band_no
		Sentinel1band(sentinel1=s, band_no=band_no) do band
			polarization(band) == polarization_
		end
	end

	band_no ≠ nothing || error("""no band with polarization: $polarization_ in $s.""")
	band_no
end

"""
	ordered_band_list(s::Sentinel1)::Vector{Int64}

Retrieve list of band numbers ordered according to the bands polarizations (see polarization_sort)
"""
function ordered_band_list(s::Sentinel1)::Vector{Int64}
	collect(band_no(s, polarization_=pol) for pol in polarizations(s))
end



function Base.lastindex(s::Sentinel1, d)
	@unpack n_bands, n_rows, n_cols = size(s)
	if d == 1
		n_bands
	elseif d == 2
		n_rows
	else
		n_cols
	end
end

# bands, rows and cols are all 1-indexed.
Base.firstindex(s::Sentinel1, d) = 1



"""
	getindex(s::Sentinel1, bands::UnitRange{Int} rows::UnitRange{Int}, cols::UnitRange{Int})

Return amplitude image for the specified 1-indexed `bands`, `rows` and `cols`.

The returned array has size: (n_cols, n_rows, n_bands). The bands are guaranteed to
be read in order of polarization. See `polarization_sort`.
"""
function Base.getindex(s::Sentinel1GRD, bands::UnitRange{Int}, rows::UnitRange{Int}, cols::UnitRange{Int})
	@unpack n_bands, n_rows, n_cols = size(s)

	bands_ok = all(x -> x ∈ ordered_band_list(s), (bands[begin], bands[end]))
	rows_ok = 1 ≤ rows[begin] ≤ rows[end] ≤ n_rows
	cols_ok = 1 ≤ cols[begin] ≤ cols[end] ≤ n_cols
	all_ok = bands_ok && rows_ok && cols_ok

	all_ok || throw(DomainError((bands, rows, cols),
		"getindex for $s must be within ranges (1:$n_bands, 1:$n_rows, 1:$n_cols).")
	)
	
	# convert array to output Sentinel1's parametric type (default is Float32).
	s.dtype.(ArchGDAL.read(s.dataset, ordered_band_list(s)[bands], rows, cols))
end


