note
	description: "[
		What one process did during one interval: rates from two samples of
		the same identity. A rate is never formed across two identities, and a
		counter that ran backward or a rate the machine could not produce makes
		that group invalid rather than clamped (DR-008).
	]"
	author: "Larry Rix"

class
	TM_PROCESS_ACTIVITY

create
	make_from_pair,
	make_born,
	make_decoded

feature {NONE} -- Initialization

	make_from_pair (a_before, a_after: TM_PROCESS_SAMPLE; a_seconds: REAL_64; a_logical_processors: INTEGER)
			-- Survivor: rates over `a_seconds' between `a_before' and `a_after'.
		require
			same_identity: a_before.id ~ a_after.id
			positive_time: a_seconds > 0.0
			processors: a_logical_processors > 0
			not_idle: not a_after.id.is_idle_pseudo_process
		do
			id := a_after.id
			create name.make_from_string (a_after.name)
			parent_pid := a_after.parent_pid
			session := a_after.session
			threads := a_after.threads
			logical_processors := a_logical_processors
			if both_cpu (a_before, a_after) then
				if is_possible_cores (pair_cores (a_before, a_after, a_seconds), a_logical_processors) then
					stored_cores := pair_cores (a_before, a_after, a_seconds)
					cpu_status := {TM_READING_STATUS}.Available
				else
					cpu_status := {TM_READING_STATUS}.Invalid
				end
			else
				cpu_status := worse_of (a_before.cpu_status, a_after.cpu_status)
			end
			if both_io (a_before, a_after) then
				if is_possible_bps (a_before, a_after) then
					stored_read_bps := (a_after.read_bytes - a_before.read_bytes) / a_seconds
					stored_write_bps := (a_after.write_bytes - a_before.write_bytes) / a_seconds
					io_status := {TM_READING_STATUS}.Available
				else
					io_status := {TM_READING_STATUS}.Invalid
				end
			else
				io_status := worse_of (a_before.io_status, a_after.io_status)
			end
			memory_status := a_after.memory_status
			if memory_status = {TM_READING_STATUS}.Available then
				stored_working_set := a_after.working_set
				stored_private_bytes := a_after.private_bytes
				stored_handles := a_after.handles
			end
		ensure
			identity_kept: id ~ a_after.id and name.same_string (a_after.name)
			not_new: not is_new
			cpu_rate_when_valid: (both_cpu (a_before, a_after) and then is_possible_cores (pair_cores (a_before, a_after, a_seconds), a_logical_processors))
				implies (cpu_status = {TM_READING_STATUS}.Available and cpu_cores = pair_cores (a_before, a_after, a_seconds))
			cpu_invalid_when_impossible: (both_cpu (a_before, a_after) and then not is_possible_cores (pair_cores (a_before, a_after, a_seconds), a_logical_processors))
				implies cpu_status = {TM_READING_STATUS}.Invalid
			cpu_reason_kept: not both_cpu (a_before, a_after) implies cpu_status = worse_of (a_before.cpu_status, a_after.cpu_status)
			io_rate_when_valid: (both_io (a_before, a_after) and then is_possible_bps (a_before, a_after))
				implies (io_status = {TM_READING_STATUS}.Available
					and io_read_bps = (a_after.read_bytes - a_before.read_bytes) / a_seconds
					and io_write_bps = (a_after.write_bytes - a_before.write_bytes) / a_seconds)
			io_invalid_when_backward: (both_io (a_before, a_after) and then not is_possible_bps (a_before, a_after))
				implies io_status = {TM_READING_STATUS}.Invalid
			io_reason_kept: not both_io (a_before, a_after) implies io_status = worse_of (a_before.io_status, a_after.io_status)
			memory_is_gauge: memory_status = a_after.memory_status
		end

	make_born (a_after: TM_PROCESS_SAMPLE; a_logical_processors: INTEGER)
			-- Newcomer: no rates this frame; memory is a gauge and is copied.
		require
			processors: a_logical_processors > 0
			not_idle: not a_after.id.is_idle_pseudo_process
		do
			id := a_after.id
			create name.make_from_string (a_after.name)
			parent_pid := a_after.parent_pid
			session := a_after.session
			threads := a_after.threads
			logical_processors := a_logical_processors
			is_new := True
			cpu_status := {TM_READING_STATUS}.Unavailable
			io_status := {TM_READING_STATUS}.Unavailable
			memory_status := a_after.memory_status
			if memory_status = {TM_READING_STATUS}.Available then
				stored_working_set := a_after.working_set
				stored_private_bytes := a_after.private_bytes
				stored_handles := a_after.handles
			end
		ensure
			identity_kept: id ~ a_after.id and name.same_string (a_after.name)
			new: is_new
			no_rates: cpu_status = {TM_READING_STATUS}.Unavailable and io_status = {TM_READING_STATUS}.Unavailable
			memory_is_gauge: memory_status = a_after.memory_status
		end

	make_decoded (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32; a_parent_pid: INTEGER_64;
			a_session, a_threads, a_handles: INTEGER; a_is_new: BOOLEAN; a_logical_processors: INTEGER;
			a_cpu_status: INTEGER; a_cores: REAL_64;
			a_memory_status: INTEGER; a_working_set, a_private_bytes: INTEGER_64;
			a_io_status: INTEGER; a_read_bps, a_write_bps: REAL_64)
			-- Activity rebuilt from a recording. Every value passes the same
			-- checks as a live one, so a damaged file yields invalid, never impossible.
		require
			processors: a_logical_processors > 0
			not_idle: not a_id.is_idle_pseudo_process
			identity_fields_non_negative: a_parent_pid >= 0 and a_session >= 0 and a_threads >= 0 and a_handles >= 0
				-- A damaged line is refused by the codec, never repaired here (review issue 11).
			known_statuses: a_cpu_status >= {TM_READING_STATUS}.Available and a_cpu_status <= {TM_READING_STATUS}.Invalid
				and a_memory_status >= {TM_READING_STATUS}.Available and a_memory_status <= {TM_READING_STATUS}.Invalid
				and a_io_status >= {TM_READING_STATUS}.Available and a_io_status <= {TM_READING_STATUS}.Invalid
		do
			id := a_id
			create name.make_from_string (a_name)
			parent_pid := a_parent_pid
			session := a_session
			threads := a_threads
			logical_processors := a_logical_processors
			is_new := a_is_new
			if a_cpu_status /= {TM_READING_STATUS}.Available then
				cpu_status := a_cpu_status
			elseif not a_is_new and then is_possible_cores (a_cores, a_logical_processors) then
				stored_cores := a_cores
				cpu_status := {TM_READING_STATUS}.Available
			else
				cpu_status := {TM_READING_STATUS}.Invalid
			end
			if a_io_status /= {TM_READING_STATUS}.Available then
				io_status := a_io_status
			elseif not a_is_new and then is_possible_rate (a_read_bps) and then is_possible_rate (a_write_bps) then
				stored_read_bps := a_read_bps
				stored_write_bps := a_write_bps
				io_status := {TM_READING_STATUS}.Available
			else
				io_status := {TM_READING_STATUS}.Invalid
			end
			if a_memory_status /= {TM_READING_STATUS}.Available then
				memory_status := a_memory_status
			elseif a_working_set >= 0 and a_private_bytes >= 0 then
				stored_working_set := a_working_set
				stored_private_bytes := a_private_bytes
				stored_handles := a_handles
				memory_status := {TM_READING_STATUS}.Available
			else
				memory_status := {TM_READING_STATUS}.Invalid
			end
		ensure
			identity_kept: id ~ a_id and name.same_string (a_name)
			new_kept: is_new = a_is_new
			cpu_checked: cpu_status = {TM_READING_STATUS}.Available implies
				(a_cpu_status = {TM_READING_STATUS}.Available and is_possible_cores (a_cores, a_logical_processors) and cpu_cores = a_cores)
			cpu_refused: (a_cpu_status = {TM_READING_STATUS}.Available and not a_is_new and not is_possible_cores (a_cores, a_logical_processors))
				implies cpu_status = {TM_READING_STATUS}.Invalid
			io_checked: io_status = {TM_READING_STATUS}.Available implies
				(a_io_status = {TM_READING_STATUS}.Available and a_read_bps >= 0.0 and a_write_bps >= 0.0)
			newcomer_cpu_refused: (a_is_new and a_cpu_status = {TM_READING_STATUS}.Available) implies cpu_status = {TM_READING_STATUS}.Invalid
			newcomer_io_refused: (a_is_new and a_io_status = {TM_READING_STATUS}.Available) implies io_status = {TM_READING_STATUS}.Invalid
			memory_checked: memory_status = {TM_READING_STATUS}.Available implies
				(a_memory_status = {TM_READING_STATUS}.Available and a_working_set >= 0 and a_private_bytes >= 0)
		end

feature -- Access

	id: TM_PROCESS_ID
			-- Identity.

	name: STRING_32
			-- Image name.

	parent_pid: INTEGER_64
			-- Pid of the creator.

	session: INTEGER
			-- Logon session.

	threads: INTEGER
			-- Thread count at the end of the interval.

	logical_processors: INTEGER
			-- Logical processors of the machine, for percent of machine.

	cpu_status, memory_status, io_status: INTEGER
			-- Status per resource group.

	cpu_cores: REAL_64
			-- CPU used, in cores (1.0 = one logical processor fully busy).
		require
			cpu_available: cpu_status = {TM_READING_STATUS}.Available
		do
			Result := stored_cores
		ensure
			non_negative: Result >= 0.0
		end

	cpu_percent: REAL_64
			-- CPU used, percent of the whole machine.
		require
			cpu_available: cpu_status = {TM_READING_STATUS}.Available
		do
			Result := stored_cores * 100.0 / logical_processors
		ensure
			non_negative: Result >= 0.0
		end

	io_read_bps: REAL_64
			-- Bytes read per second.
		require
			io_available: io_status = {TM_READING_STATUS}.Available
		do
			Result := stored_read_bps
		ensure
			non_negative: Result >= 0.0
		end

	io_write_bps: REAL_64
			-- Bytes written per second.
		require
			io_available: io_status = {TM_READING_STATUS}.Available
		do
			Result := stored_write_bps
		ensure
			non_negative: Result >= 0.0
		end

	working_set: INTEGER_64
			-- Resident bytes at the end of the interval.
		require
			memory_available: memory_status = {TM_READING_STATUS}.Available
		do
			Result := stored_working_set
		end

	private_bytes: INTEGER_64
			-- Private committed bytes at the end of the interval.
		require
			memory_available: memory_status = {TM_READING_STATUS}.Available
		do
			Result := stored_private_bytes
		end

	handles: INTEGER
			-- Handle count at the end of the interval.
		require
			memory_available: memory_status = {TM_READING_STATUS}.Available
		do
			Result := stored_handles
		end

	amount_of (a_resource: INTEGER): REAL_64
			-- How much of `a_resource' this activity used, for ranking.
		require
			known_resource: a_resource >= {TM_RESOURCE}.Cpu and a_resource <= {TM_RESOURCE}.Io_total
			measured: has_resource (a_resource)
		do
			inspect a_resource
			when {TM_RESOURCE}.Cpu then
				Result := stored_cores
			when {TM_RESOURCE}.Memory then
				Result := stored_private_bytes.to_double
			when {TM_RESOURCE}.Io_read then
				Result := stored_read_bps
			when {TM_RESOURCE}.Io_write then
				Result := stored_write_bps
			else
				Result := stored_read_bps + stored_write_bps
			end
		ensure
			non_negative: Result >= 0.0
		end

feature -- Status report

	is_new: BOOLEAN
			-- Was this identity born during the interval?

	has_resource (a_resource: INTEGER): BOOLEAN
			-- Is `a_resource' measured for this activity?
		require
			known_resource: a_resource >= {TM_RESOURCE}.Cpu and a_resource <= {TM_RESOURCE}.Io_total
		do
			inspect a_resource
			when {TM_RESOURCE}.Cpu then
				Result := cpu_status = {TM_READING_STATUS}.Available
			when {TM_RESOURCE}.Memory then
				Result := memory_status = {TM_READING_STATUS}.Available
			else
				Result := io_status = {TM_READING_STATUS}.Available
			end
		end

feature -- Contract support

	Cpu_tolerance: REAL_64 = 1.05
			-- Sampling jitter allowed above all processors busy (DR-008).

	both_cpu (a_before, a_after: TM_PROCESS_SAMPLE): BOOLEAN
			-- Are both CPU groups available?
		do
			Result := a_before.cpu_status = {TM_READING_STATUS}.Available
				and a_after.cpu_status = {TM_READING_STATUS}.Available
		end

	both_io (a_before, a_after: TM_PROCESS_SAMPLE): BOOLEAN
			-- Are both IO groups available?
		do
			Result := a_before.io_status = {TM_READING_STATUS}.Available
				and a_after.io_status = {TM_READING_STATUS}.Available
		end

	pair_cores (a_before, a_after: TM_PROCESS_SAMPLE; a_seconds: REAL_64): REAL_64
			-- Cores used between the two samples; negative when a counter ran backward.
		require
			both: both_cpu (a_before, a_after)
			positive_time: a_seconds > 0.0
		do
			Result := (((a_after.user_ticks + a_after.kernel_ticks) - (a_before.user_ticks + a_before.kernel_ticks)).to_double
				/ {TM_CLOCK}.Ticks_per_second.to_double) / a_seconds
		end

	is_possible_cores (a_cores: REAL_64; a_logical_processors: INTEGER): BOOLEAN
			-- Could a process truly use `a_cores' on this machine?
		do
			Result := not (a_cores.is_nan or a_cores.is_positive_infinity or a_cores.is_negative_infinity)
				and then a_cores >= 0.0 and then a_cores <= a_logical_processors * Cpu_tolerance
		end

	is_possible_bps (a_before, a_after: TM_PROCESS_SAMPLE): BOOLEAN
			-- Did neither IO counter run backward?
		require
			both: both_io (a_before, a_after)
		do
			Result := a_after.read_bytes >= a_before.read_bytes and a_after.write_bytes >= a_before.write_bytes
		end

	is_possible_rate (a_bps: REAL_64): BOOLEAN
			-- Is `a_bps' a byte rate a process could truly show: finite and not negative?
		do
			Result := not (a_bps.is_nan or a_bps.is_positive_infinity or a_bps.is_negative_infinity) and then a_bps >= 0.0
		end

	worse_of (a_first, a_second: INTEGER): INTEGER
			-- The more useful reason of two statuses: access denied, then not
			-- supported, then invalid, then unavailable, then available.
		do
			if reason_rank (a_first) >= reason_rank (a_second) then
				Result := a_first
			else
				Result := a_second
			end
		ensure
			one_of_them: Result = a_first or Result = a_second
		end

feature {NONE} -- Implementation

	stored_cores: REAL_64
	stored_read_bps, stored_write_bps: REAL_64
	stored_working_set, stored_private_bytes: INTEGER_64
	stored_handles: INTEGER

	reason_rank (a_status: INTEGER): INTEGER
			-- Usefulness of `a_status' as an explanation.
		do
			inspect a_status
			when {TM_READING_STATUS}.Access_denied then
				Result := 4
			when {TM_READING_STATUS}.Not_supported then
				Result := 3
			when {TM_READING_STATUS}.Invalid then
				Result := 2
			when {TM_READING_STATUS}.Unavailable then
				Result := 1
			else
				Result := 0
			end
		end

invariant
	processors: logical_processors > 0
	threads_non_negative: threads >= 0
	not_idle: not id.is_idle_pseudo_process
	cpu_status_known: cpu_status >= {TM_READING_STATUS}.Available and cpu_status <= {TM_READING_STATUS}.Invalid
	memory_status_known: memory_status >= {TM_READING_STATUS}.Available and memory_status <= {TM_READING_STATUS}.Invalid
	io_status_known: io_status >= {TM_READING_STATUS}.Available and io_status <= {TM_READING_STATUS}.Invalid
	born_has_no_rates: is_new implies (cpu_status /= {TM_READING_STATUS}.Available and io_status /= {TM_READING_STATUS}.Available)
	cpu_possible: cpu_status = {TM_READING_STATUS}.Available implies (stored_cores >= 0.0 and stored_cores <= logical_processors * Cpu_tolerance)
	cpu_zero_unless_set: cpu_status /= {TM_READING_STATUS}.Available implies stored_cores = 0.0
	io_non_negative: io_status = {TM_READING_STATUS}.Available implies (stored_read_bps >= 0.0 and stored_write_bps >= 0.0)
	io_zero_unless_set: io_status /= {TM_READING_STATUS}.Available implies (stored_read_bps = 0.0 and stored_write_bps = 0.0)
	memory_zero_unless_set: memory_status /= {TM_READING_STATUS}.Available implies
		(stored_working_set = 0 and stored_private_bytes = 0 and stored_handles = 0)

end
