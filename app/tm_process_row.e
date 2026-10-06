note
	description: "[
		One process grid row, preformatted once per frame (A-106): text for
		each column through TM_FORMAT, and a numeric sort key per column. A
		group that is not available shows its status word, never 0, and its
		key is -1 so it sorts below every measured value.
	]"
	author: "Larry Rix"

class
	TM_PROCESS_ROW

create
	make

feature {NONE} -- Initialization

	make (a_activity: TM_PROCESS_ACTIVITY; a_format: TM_FORMAT; a_is_self: BOOLEAN; a_status: READABLE_STRING_32)
			-- Row for `a_activity'; `a_is_self' marks this tool's own row (FR-053, I-008); `a_status' is
			-- "App", "Not responding", or empty for a background process.
		do
			id := a_activity.id
			create status_text.make_from_string (a_status)
			status_key := a_status.as_lower
			is_self := a_is_self
			if a_is_self then
				name_text := {STRING_32} "* " + a_activity.name
			else
				create name_text.make_from_string (a_activity.name)
			end
			name_key := a_activity.name.as_lower
			pid_key := a_activity.id.pid
			pid_text := pid_key.out.to_string_32
			threads_key := a_activity.threads
			threads_text := threads_key.out.to_string_32
			if a_activity.cpu_status = {TM_READING_STATUS}.Available then
				cpu_key := a_activity.cpu_percent
				cpu_text := a_format.percent (a_activity.cpu_percent)
			else
				cpu_key := -1.0
				cpu_text := a_format.status_word (a_activity.cpu_status)
			end
			if a_activity.memory_status = {TM_READING_STATUS}.Available then
				private_key := a_activity.private_bytes.to_double
				private_text := a_format.bytes (a_activity.private_bytes)
				working_set_key := a_activity.working_set.to_double
				working_set_text := a_format.bytes (a_activity.working_set)
			else
				private_key := -1.0
				working_set_key := -1.0
				private_text := a_format.status_word (a_activity.memory_status)
				working_set_text := private_text.twin
			end
			if a_activity.io_status = {TM_READING_STATUS}.Available then
				read_key := a_activity.io_read_bps
				write_key := a_activity.io_write_bps
				read_text := a_format.bytes_per_second (a_activity.io_read_bps)
				write_text := a_format.bytes_per_second (a_activity.io_write_bps)
			else
				read_key := -1.0
				write_key := -1.0
				read_text := a_format.status_word (a_activity.io_status)
				write_text := read_text.twin
			end
		ensure
			identity_kept: id ~ a_activity.id
			self_kept: is_self = a_is_self
		end

feature -- Access

	status_text: STRING_32
	status_key: STRING_32

	id: TM_PROCESS_ID
	is_self: BOOLEAN

	name_text, pid_text, cpu_text, private_text, working_set_text, read_text, write_text, threads_text: STRING_32
			-- Column texts.

	name_key: STRING_32
	pid_key: INTEGER_64
	threads_key: INTEGER
	cpu_key, private_key, working_set_key, read_key, write_key: REAL_64
			-- Sort keys; -1 when the group is not available.

end
