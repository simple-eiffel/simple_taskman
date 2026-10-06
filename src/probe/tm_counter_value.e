note
	description: "[
		One PDH counter instance's formatted value and its PDH status. Only
		PDH_CSTATUS_VALID_DATA and PDH_CSTATUS_NEW_DATA count as valid; the
		system source turns anything else into an invalid reading.
	]"
	author: "Larry Rix"

class
	TM_COUNTER_VALUE

create
	make

feature {NONE} -- Initialization

	make (a_instance: READABLE_STRING_32; a_value: REAL_64; a_pdh_status: INTEGER)
			-- Value `a_value' of instance `a_instance' with PDH status `a_pdh_status'.
		do
			create instance.make_from_string (a_instance)
			stored_value := a_value
			pdh_status := a_pdh_status
		ensure
			kept: instance.same_string (a_instance) and pdh_status = a_pdh_status
		end

feature -- Access

	instance: STRING_32
			-- Instance name, for example "0,3", "_Total", or "" for a single counter.

	pdh_status: INTEGER
			-- CStatus reported by PDH.

	value: REAL_64
			-- The formatted value.
		require
			valid: is_valid
		do
			Result := stored_value
		end

feature -- Status report

	is_valid: BOOLEAN
			-- Did PDH report valid or new data?
		do
			Result := pdh_status = Pdh_cstatus_valid_data or pdh_status = Pdh_cstatus_new_data
		end

feature -- Constants

	Pdh_cstatus_valid_data: INTEGER = 0
	Pdh_cstatus_new_data: INTEGER = 1

feature {NONE} -- Implementation

	stored_value: REAL_64

end
