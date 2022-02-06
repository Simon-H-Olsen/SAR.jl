const VALID_POLS = ("HH", "HV", "VV", "VH")



function polarization_sort(pol)
	if pol == "HH"
		1
	elseif pol == "HV"
		2
	elseif pol == "VV"
		3
	elseif pol == "VH"
		4
	else
		error("invalid pol: $pol, for polarization_sort.")
	end
end