note
	description: "[
		Mixin exporting the metric registry. Under SCOOP a `once' is per
		processor, so each processor builds its own read-only registry and no
		processor ever reaches into another's.
	]"
	author: "Larry Rix"

class
	TM_SHARED_METRICS

feature -- Access

	metrics: TM_METRICS
			-- The registry, built once on this processor.
		once
			create Result.make
		ensure
			complete: Result.count = {TM_METRICS}.Last_code
		end

end
