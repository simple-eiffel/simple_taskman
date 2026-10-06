note
	description: "[
		For every registered metric, whether this machine supplies it and, if
		not, why; plus which process source is in use and, when the native
		table was refused, the self-check's reason. What the capability panel
		and `taskman_cli capabilities' show.
	]"
	author: "Larry Rix"

class
	TM_CAPABILITIES

inherit
	TM_SHARED_METRICS

create
	make,
	make_empty

feature {NONE} -- Initialization

	make (a_system: TM_SYSTEM_SOURCE; a_process_source_kind: READABLE_STRING_8; a_fallback_reason: READABLE_STRING_32)
			-- Report for `a_system' with process source `a_process_source_kind'.
		require
			kind_given: not a_process_source_kind.is_empty
		do
			make_empty
			across metrics.codes as ic loop
				put (ic, a_system.support_of (ic), a_system.support_reason (ic))
			end
			set_process_source (a_process_source_kind, a_fallback_reason)
		ensure
			every_metric: count = metrics.count
			as_declared: across metrics.codes as ic all support_of (ic) = a_system.support_of (ic) end
			kind_kept: process_source_kind.same_string (a_process_source_kind)
			reason_kept: fallback_reason.same_string (a_fallback_reason)
		end

	make_empty
			-- Report with nothing in it yet; filled by `put' (the codec decodes this way).
		do
			create support.make (32)
			create reasons.make (32)
			create process_source_kind.make_empty
			create fallback_reason.make_empty
		ensure
			empty: count = 0
		end

feature -- Access

	support_of (a_code: INTEGER): INTEGER
			-- Available, or why metric `a_code' is not supplied.
		require
			present: has (a_code)
		do
			Result := support [a_code]
		ensure
			known_status: Result >= {TM_READING_STATUS}.Available and Result <= {TM_READING_STATUS}.Invalid
		end

	reason_of (a_code: INTEGER): STRING_32
			-- Why metric `a_code' is not supplied; empty when it is.
		require
			present: has (a_code)
		do
			if attached reasons.item (a_code) as al_reason then
				Result := al_reason.twin
			else
				create Result.make_empty
			end
		end

	process_source_kind: STRING_8
			-- "native", "documented", or "scripted"; empty until set.

	fallback_reason: STRING_32
			-- Why the native table was not used; empty when it was.

	count: INTEGER
			-- Metrics reported.
		do
			Result := support.count
		end

feature -- Status report

	has (a_code: INTEGER): BOOLEAN
			-- Is metric `a_code' reported?
		do
			Result := support.has (a_code)
		end

	is_supported (a_code: INTEGER): BOOLEAN
			-- Does this machine supply metric `a_code'?
		require
			present: has (a_code)
		do
			Result := support_of (a_code) = {TM_READING_STATUS}.Available
		end

feature -- Element change

	put (a_code: INTEGER; a_status: INTEGER; a_reason: READABLE_STRING_32)
			-- Report metric `a_code' with `a_status' and `a_reason'.
		require
			known_metric: metrics.has_code (a_code)
			not_yet: not has (a_code)
			known_status: a_status >= {TM_READING_STATUS}.Available and a_status <= {TM_READING_STATUS}.Invalid
		do
			support.force (a_status, a_code)
			reasons.force (create {STRING_32}.make_from_string (a_reason), a_code)
		ensure
			reported: has (a_code) and support_of (a_code) = a_status
			reason_kept: reason_of (a_code).same_string (a_reason)
			one_more: count = old count + 1
			others_unchanged: support_model.removed (a_code) |=| old support_model
		end

	set_process_source (a_kind: READABLE_STRING_8; a_fallback_reason: READABLE_STRING_32)
			-- Record the process source in use and why native was refused.
		require
			kind_given: not a_kind.is_empty
		do
			create process_source_kind.make_from_string (a_kind)
			create fallback_reason.make_from_string (a_fallback_reason)
		ensure
			kind_kept: process_source_kind.same_string (a_kind)
			reason_kept: fallback_reason.same_string (a_fallback_reason)
		end

feature -- Model

	support_model: MML_MAP [INTEGER, INTEGER]
			-- Support status by metric code.
		do
			create Result
			across support as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = count
		end

feature {NONE} -- Implementation

	support: HASH_TABLE [INTEGER, INTEGER]
	reasons: HASH_TABLE [STRING_32, INTEGER]

invariant
	parallel: support.count = reasons.count

end
