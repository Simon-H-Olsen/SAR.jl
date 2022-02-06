

const Sentinel1GRD_IW_test_file = "./data/S1A_IW_GRDH_1SDV_20201022T060529_20201022T060554_034905_0411DD_9560.SAFE"
const Sentinel1GRD_EW_test_file = "./data/S1A_EW_GRDM_1SSH_20220109T033054_20220109T033158_041378_04EB6D_A333.SAFE"



@testset "size(s::Sentinel1)" begin

	# test size(s::Sentinel1GRD) returns correct on real data
	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		@unpack n_bands, n_rows, n_cols = size(s)
		@test n_bands == 2 && n_rows == 16671 && n_cols == 26593
	end


	Sentinel1GRD(safe_file=Sentinel1GRD_EW_test_file) do s
		@unpack n_bands, n_rows, n_cols = size(s)
		@test n_bands == 1 && n_rows == 10864 && n_cols == 10450
	end



	# test size(s::Sentinel1GRD) returns an error if ArchGDAL.nraster returns 0,
	# indicating it could not read the number of bands.

	Mocking.activate()
	patch = @patch ArchGDAL.nraster(ds::ArchGDAL.AbstractDataset) = 0

	# Apply the patch which will modify the behaviour for our test
	apply(patch) do
		Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
			@test_throws ErrorException("""
				could not read the number of bands for Sentinel1GRD{Float32}\
				("./data/S1A_IW_GRDH_1SDV_20201022T060529_20201022T060554_03490\
				5_0411DD_9560.SAFE").""") size(s)
		end
	end


	# TODO: test size(s::Sentinel1GRD) returns an error if height or width is reported less than 1.

end


@testset "polarisation(b::Sentinel1band)" begin

	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		Sentinel1band(sentinel1=s, band_no=1) do b
			@test polarization(b) == "VH"
		end
	end


	# test polarisation(b::Sentinel1band) returns an error if band metadata does not have "POLARISATION=" element.

	Mocking.activate()
	patch = @patch ArchGDAL.metadata(b::ArchGDAL.AbstractRasterBand) = []

	apply(patch) do
		Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
			Sentinel1band(sentinel1=s, band_no=1) do b
				@test_throws ErrorException("""
					could not find polarization from metadata for $b.""") polarization(b)
			end
		end
	end

	# test polarisation(b::Sentinel1band returns an error if band metadata contains an invalid polarisation.

	Mocking.activate()
	patch = @patch ArchGDAL.metadata(b::ArchGDAL.AbstractRasterBand) = ["POLARIZATION=VVH"]

	apply(patch) do
		Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
			Sentinel1band(sentinel1=s, band_no=1) do b
				@test_throws ErrorException("""
				invalid polarization: VVH for $b.""") polarization(b)
			end
		end
	end

end


@testset "polarizations(s::Sentinel1)" begin
	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		@test polarizations(s) == ["VV", "VH"]
	end

	Sentinel1GRD(safe_file=Sentinel1GRD_EW_test_file) do s
		@test polarizations(s) == ["HH"]
	end

end


@testset "band_no(s::Sentinel1, polarization::String)" begin


	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		@test band_no(s, polarization_="VH") === 1
	end


	# test if polarisation is not present.
	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		@test_throws ErrorException("""
			no band with polarization: HV in $s.""") band_no(s, polarization_="HV")
	end


end


@testset "ordered_band_list(s::Sentinel1)::Vector{Int64}" begin
	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		@test ordered_band_list(s) == [2, 1]
	end
	
	Sentinel1GRD(safe_file=Sentinel1GRD_EW_test_file) do s
		@test ordered_band_list(s) == [1]
	end
	
end


@testset "Base.getindex(s::Sentinel1GRD, bands::UnitRange{Int}, rows::UnitRange{Int}, cols::UnitRange{Int})" begin
	Sentinel1GRD{Float64}(safe_file=Sentinel1GRD_IW_test_file) do s
		window = s[begin:end, 10001:10010, 10001:10020]
		@test eltype(window) == Float64
		@test size(window) == (20, 10, 2)
	end


	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		window = s[begin:end, 10001:10010, 10001:10020]
		@test eltype(window) == Float32
		@test size(window) == (20, 10, 2)
	end


	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		@unpack n_bands, n_rows, n_cols = size(s)

		window = s[begin:end, begin:end, 10001:10010]
		@test eltype(window) == Float32
		@test size(window) == (10, n_rows, 2)
	end


	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		@unpack n_bands, n_rows, n_cols = size(s)

		window = s[begin:end, 10001:10010, begin:end]
		@test eltype(window) == Float32
		@test size(window) == (n_cols, 10, 2)
	end


	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		@unpack n_bands, n_rows, n_cols = size(s)

		@test_throws DomainError((0:1, 10:20, 10:20), """
			getindex for $s must be within ranges \
				(1:$n_bands, 1:$n_rows, 1:$n_cols).""") s[0:1, 10:20, 10:20]

		@test_throws DomainError((1:2, (-10):20, 10:20), """
			getindex for $s must be within ranges \
				(1:$n_bands, 1:$n_rows, 1:$n_cols).""") s[begin:end, (-10):20, 10:20]

		@test_throws DomainError((1:2, 10:20, (-10):20), """
			getindex for $s must be within ranges \
				(1:$n_bands, 1:$n_rows, 1:$n_cols).""") s[begin:end, 10:20, (-10):20]

		@test_throws DomainError((1:(n_bands + 1), 10:20, 10:20), """
			getindex for $s must be within ranges \
				(1:$n_bands, 1:$n_rows, 1:$n_cols).""") s[begin:(n_bands + 1), 10:20, 10:20]

		@test_throws DomainError((1:2, 10:(n_rows + 1), 10:20), """
			getindex for $s must be within ranges \
				(1:$n_bands, 1:$n_rows, 1:$n_cols).""") s[begin:end, 10:(n_rows + 1), 10:20]


		@test_throws DomainError((1:2, 10:20, 10:(n_cols + 1)), """
			getindex for $s must be within ranges \
				(1:$n_bands, 1:$n_rows, 1:$n_cols).""") s[begin:end, 10:20, 10:(n_cols + 1)]


	end

end


@testset "views(s::Sentinel1GRD, tile_height, tile_width)" begin
	Sentinel1GRD(safe_file=Sentinel1GRD_IW_test_file) do s
		@unpack n_bands, n_rows, n_cols = size(s)


		tile_height, tile_width = 128, 128
		tile_iter = views(s, tile_height, tile_width)
		@test length(tile_iter[begin,begin:end]) == convert(Int64, ceil(n_cols / tile_width))
		@test length(tile_iter[begin:end,begin]) == convert(Int64, ceil(n_rows / tile_height))
	end

	Sentinel1GRD(safe_file=Sentinel1GRD_EW_test_file) do s
		@unpack n_bands, n_rows, n_cols = size(s)


		tile_height, tile_width = 128, 128
		tile_iter = views(s, tile_height, tile_width)
		@test length(tile_iter[begin,begin:end]) == convert(Int64, ceil(n_cols / tile_width))
		@test length(tile_iter[begin:end,begin]) == convert(Int64, ceil(n_rows / tile_height))
	end
end


