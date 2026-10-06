note
	description: "[
		Where system-wide readings come from. Support for each metric is
		decided once, at creation, by trying its source, and never changes. A
		metric that is not supported reads as such, with the reason kept.
		The first refresh reports rate counters as unavailable, because PDH
		needs two collections for a rate.
	]"
	author: "Larry Rix"

deferred class
	TM_SYSTEM_SOURCE

inherit
	TM_SHARED_METRICS

feature -- Basic operations

	refresh
			-- Read every supported metric now.
		require
			open: not is_closed
		deferred
		ensure
			sealed: last_readings.is_sealed
			unsupported_reads_as_declared: across metrics.codes as ic all
				(support_of (ic) /= {TM_READING_STATUS}.Available and not metrics.metric (ic).is_instanced)
					implies last_readings.reading (ic, {STRING_32} "").status = support_of (ic) end
			supported_present: across metrics.codes as ic all
				(support_of (ic) = {TM_READING_STATUS}.Available and not metrics.metric (ic).is_instanced)
					implies last_readings.has (ic, {STRING_32} "") end
				-- A supported metric never reads "not supported" by being left out (review issue 6).
		end

	close
			-- Release native resources.
		deferred
		ensure
			closed: is_closed
		end

feature -- Access

	last_readings: TM_READINGS
			-- Readings of the last refresh; sealed.

	support_of (a_code: INTEGER): INTEGER
			-- Whether this machine supplies metric `a_code': Available, or the reason it does not.
		require
			known_metric: metrics.has_code (a_code)
		deferred
		ensure
			known_status: Result >= {TM_READING_STATUS}.Available and Result <= {TM_READING_STATUS}.Invalid
		end

	support_reason (a_code: INTEGER): STRING_32
			-- Why metric `a_code' is not supplied, for example "no thermal zone instance"; empty when it is.
		require
			known_metric: metrics.has_code (a_code)
		deferred
		ensure
			explained: support_of (a_code) /= {TM_READING_STATUS}.Available implies not Result.is_empty
			blank_when_supported: support_of (a_code) = {TM_READING_STATUS}.Available implies Result.is_empty
		end

	supported_codes: ARRAYED_LIST [INTEGER]
			-- Codes this machine supplies; a fresh list each call.
		do
			create Result.make (metrics.count)
			across metrics.codes as ic loop
				if support_of (ic) = {TM_READING_STATUS}.Available then
					Result.extend (ic)
				end
			end
		ensure
			each_supported: across Result as ic all support_of (ic) = {TM_READING_STATUS}.Available end
		end

	logical_processors: INTEGER
			-- Logical processors across all processor groups.
		deferred
		ensure
			positive: Result > 0
		end

feature -- Status report

	is_closed: BOOLEAN
			-- Have native resources been released?

feature {NONE} -- Implementation

	status_reading (a_status: INTEGER): TM_READING
			-- A reading that carries no value, only `a_status'.
		require
			not_available: a_status >= {TM_READING_STATUS}.Unavailable and a_status <= {TM_READING_STATUS}.Invalid
		do
			inspect a_status
			when {TM_READING_STATUS}.Unavailable then
				create Result.make_unavailable
			when {TM_READING_STATUS}.Not_supported then
				create Result.make_not_supported
			when {TM_READING_STATUS}.Access_denied then
				create Result.make_access_denied
			else
				create Result.make_invalid
			end
		ensure
			status_kept: Result.status = a_status
		end

invariant
	readings_sealed: last_readings.is_sealed

end
