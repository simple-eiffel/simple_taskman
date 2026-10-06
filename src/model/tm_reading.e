note
	description: "[
		One observation of one metric: a measured value, or the stated reason
		there is none. A value can only enter through `make_measured', which
		checks it against its metric, so an impossible number cannot be stored.
	]"
	author: "Larry Rix"

class
	TM_READING

create
	make_measured,
	make_unavailable,
	make_not_supported,
	make_access_denied,
	make_invalid

feature {NONE} -- Initialization

	make_measured (a_value: REAL_64; a_metric: TM_METRIC)
			-- Available when `a_metric' accepts `a_value'; invalid otherwise.
		do
			if a_metric.accepts (a_value) then
				status := {TM_READING_STATUS}.Available
				stored_value := a_value
			else
				status := {TM_READING_STATUS}.Invalid
			end
		ensure
			available_when_accepted: a_metric.accepts (a_value) implies (is_available and value = a_value)
			invalid_otherwise: not a_metric.accepts (a_value) implies is_invalid
		end

	make_unavailable
			-- The source exists but gave nothing this time.
		do
			status := {TM_READING_STATUS}.Unavailable
		ensure
			unavailable: is_unavailable
		end

	make_not_supported
			-- This machine has no such source.
		do
			status := {TM_READING_STATUS}.Not_supported
		ensure
			not_supported: is_not_supported
		end

	make_access_denied
			-- The source exists; our rights do not reach it.
		do
			status := {TM_READING_STATUS}.Access_denied
		ensure
			denied: is_access_denied
		end

	make_invalid
			-- The source answered with a value that cannot be true.
		do
			status := {TM_READING_STATUS}.Invalid
		ensure
			invalid: is_invalid
		end

feature -- Access

	status: INTEGER
			-- One of the {TM_READING_STATUS} codes.

	value: REAL_64
			-- The measured value.
		require
			available: is_available
		do
			Result := stored_value
		ensure
			definition: Result = stored_value
		end

	status_name: STRING_8
			-- "available", "unavailable", "not supported", "access denied", or "invalid".
		do
			inspect status
			when {TM_READING_STATUS}.Available then
				Result := "available"
			when {TM_READING_STATUS}.Unavailable then
				Result := "unavailable"
			when {TM_READING_STATUS}.Not_supported then
				Result := "not supported"
			when {TM_READING_STATUS}.Access_denied then
				Result := "access denied"
			else
				Result := "invalid"
			end
		ensure
			named: not Result.is_empty
		end

feature -- Status report

	is_available: BOOLEAN
			-- Is there a measured value?
		do
			Result := status = {TM_READING_STATUS}.Available
		end

	is_unavailable: BOOLEAN
			-- Did the source give nothing this time?
		do
			Result := status = {TM_READING_STATUS}.Unavailable
		end

	is_not_supported: BOOLEAN
			-- Does this machine lack the source?
		do
			Result := status = {TM_READING_STATUS}.Not_supported
		end

	is_access_denied: BOOLEAN
			-- Did our rights fall short?
		do
			Result := status = {TM_READING_STATUS}.Access_denied
		end

	is_invalid: BOOLEAN
			-- Was the answer impossible?
		do
			Result := status = {TM_READING_STATUS}.Invalid
		end

feature {TM_READING} -- Implementation

	stored_value: REAL_64
			-- Zero unless available.

invariant
	status_known: status >= {TM_READING_STATUS}.Available and status <= {TM_READING_STATUS}.Invalid
	exactly_one_status: is_available xor (is_unavailable or is_not_supported or is_access_denied or is_invalid)
	value_only_when_available: not is_available implies stored_value = 0.0
	available_is_finite: is_available implies
		not (stored_value.is_nan or stored_value.is_positive_infinity or stored_value.is_negative_infinity)

end
