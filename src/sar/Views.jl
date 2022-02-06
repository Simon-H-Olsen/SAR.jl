"""
This file contains utilities for help with inspecting Sentinel1 images.

Typically you would want to access or iterate over the images in a specific way.
This file uses views over Sentinel1 images that can be used to inspect them in a
way that is suited for iteration or has the appropriate dimensions for a certain
machine learning library.



"""


function views(s::Sentinel1GRD, tile_height, tile_width)
	@unpack n_bands, n_rows, n_cols = size(s)

	Sentinel1band(sentinel1=s, band_no=1) do band
		
		 TiledIteration.TileIterator((Base.OneTo(n_rows), Base.OneTo(n_cols)), (tile_height, tile_width))

	end
end


struct FluxView
	s::Sentinel1
	tile_height
	tile_width
	tiles_per_view
	num_views
	view_array
	tile_iter
	function FluxView(s::Sentinel1, tile_height::Int64, tile_width::Int64)
		@unpack n_bands, n_rows, n_cols = size(s)

		tiles_per_view = convert(Int64, ceil(n_cols / tile_width))
		num_views = convert(Int64, ceil(n_rows / tile_height))
		
		# Flux requires image data in the form: WxHxCxN, where N denotes mini-batch size.
		view_array = zeros(s.dtype, tile_width, tile_height, n_bands, tiles_per_view)

		tile_iter = views(s, tile_height, tile_width)

		new(s, tile_height, tile_width, tiles_per_view, num_views, view_array, tile_iter)
	end
end





function Base.iterate(fv::FluxView, state=1)
	if state > fv.num_views
		return nothing
	end

	fill!(fv.view_array, 0)
	for (i, (rows, cols)) in enumerate(fv.tile_iter[state, begin:end])
		row_length = length(rows)
		col_length = length(cols)
		fv.view_array[begin:min(end, col_length), begin:min(end, row_length), begin:end, i] .= fv.s[begin:end, rows, cols]
	end
	(fv.view_array, state + 1)
end

