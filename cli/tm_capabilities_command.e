note
	description: "[
		`taskman_cli capabilities': one line per metric (name, status, reason)
		and the process source with its self-check. Builds text only.
	]"
	author: "Larry Rix"

class
	TM_CAPABILITIES_COMMAND

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make
			-- Ready to run.
		do
			create output.make_empty
		ensure
			not_run: not has_run
		end

feature -- Access

	output: STRING_32
			-- What `execute' produced.

	exit_code: INTEGER
			-- Always 0: what the machine cannot measure is an answer, not a failure.

feature -- Status report

	has_run: BOOLEAN

feature -- Execution

	execute
			-- Describe what this machine can measure.
		local
			l_tm: SIMPLE_TASKMAN
		do
			create l_tm.make
			output := describe (l_tm.capabilities, l_tm.native_self_check_passed)
			l_tm.close
			exit_code := 0
			has_run := True
		ensure
			ran: has_run
			one_line_per_metric_and_source: output.occurrences ({CHARACTER_32} '%N') = metrics.count + 1
		end

	describe (a_capabilities: TM_CAPABILITIES; a_self_check_passed: BOOLEAN): STRING_32
			-- The report for `a_capabilities'.
		require
			complete: a_capabilities.count = metrics.count
		local
			l_status: STRING_32
		do
			create Result.make (2048)
			across metrics.codes as ic loop
				if a_capabilities.is_supported (ic) then
					l_status := {STRING_32} "available"
				else
					l_status := status_name (a_capabilities.support_of (ic))
				end
				Result.append (padded (metrics.metric (ic).name.to_string_32, 26) + padded (l_status, 15)
					+ a_capabilities.reason_of (ic) + {STRING_32} "%N")
			end
			Result.append (padded ({STRING_32} "process_table", 26) + padded (a_capabilities.process_source_kind.to_string_32, 15))
			if a_self_check_passed then
				Result.append ({STRING_32} "self-check passed%N")
			else
				Result.append ({STRING_32} "native refused: " + a_capabilities.fallback_reason + {STRING_32} "%N")
			end
		ensure
			one_line_per_metric_and_source: Result.occurrences ({CHARACTER_32} '%N') = metrics.count + 1
		end

feature {NONE} -- Implementation

	status_name (a_status: INTEGER): STRING_32
			-- Words for `a_status'.
		require
			known: a_status >= {TM_READING_STATUS}.Unavailable and a_status <= {TM_READING_STATUS}.Invalid
		do
			inspect a_status
			when {TM_READING_STATUS}.Unavailable then
				Result := (create {TM_READING}.make_unavailable).status_name.to_string_32
			when {TM_READING_STATUS}.Access_denied then
				Result := (create {TM_READING}.make_access_denied).status_name.to_string_32
			when {TM_READING_STATUS}.Invalid then
				Result := (create {TM_READING}.make_invalid).status_name.to_string_32
			else
				Result := (create {TM_READING}.make_not_supported).status_name.to_string_32
			end
		end

	padded (a_text: READABLE_STRING_32; a_width: INTEGER): STRING_32
			-- `a_text' followed by spaces to `a_width', and at least one space.
		do
			create Result.make_from_string (a_text)
			from
			until
				Result.count >= a_width - 1
			loop
				Result.append_character (' ')
			end
			Result.append_character (' ')
		end

end
