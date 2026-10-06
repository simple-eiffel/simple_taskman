note
	description: "[
		One process's cumulative counters at one instant. Three status groups,
		because that is what the sources can actually deliver: the native table
		gives all three at once; the documented fallback can be denied any of
		them per process. Each group is set or denied exactly once.
	]"
	author: "Larry Rix"

class
	TM_PROCESS_SAMPLE

create
	make

feature {NONE} -- Initialization

	make (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32; a_parent_pid: INTEGER_64; a_session, a_threads: INTEGER)
			-- Sample of process `a_id' with every resource group still unset.
		require
			parent_non_negative: a_parent_pid >= 0
			session_non_negative: a_session >= 0
			threads_non_negative: a_threads >= 0
		do
			id := a_id
			create name.make_from_string (a_name)
			parent_pid := a_parent_pid
			session := a_session
			threads := a_threads
			cpu_status := {TM_READING_STATUS}.Unavailable
			memory_status := {TM_READING_STATUS}.Unavailable
			io_status := {TM_READING_STATUS}.Unavailable
		ensure
			identity_kept: id ~ a_id
			name_copied: name.same_string (a_name) and name /= a_name
			others_kept: parent_pid = a_parent_pid and session = a_session and threads = a_threads
			groups_unset: cpu_status = {TM_READING_STATUS}.Unavailable
				and memory_status = {TM_READING_STATUS}.Unavailable
				and io_status = {TM_READING_STATUS}.Unavailable
		end

feature -- Access

	id: TM_PROCESS_ID
			-- Identity.

	name: STRING_32
			-- Image name only; never a path or command line (R-7).

	parent_pid: INTEGER_64
			-- Pid of the creator; it may since have exited or been reused.

	session: INTEGER
			-- Logon session.

	threads: INTEGER
			-- Thread count.

	cpu_status: INTEGER
			-- Status of the CPU group.

	memory_status: INTEGER
			-- Status of the memory group (working set, private bytes, handles).

	io_status: INTEGER
			-- Status of the IO group.

	user_ticks: INTEGER_64
			-- Cumulative user-mode CPU time, 100 ns ticks.
		require
			cpu_available: cpu_status = {TM_READING_STATUS}.Available
		do
			Result := stored_user_ticks
		end

	kernel_ticks: INTEGER_64
			-- Cumulative kernel-mode CPU time, 100 ns ticks.
		require
			cpu_available: cpu_status = {TM_READING_STATUS}.Available
		do
			Result := stored_kernel_ticks
		end

	working_set: INTEGER_64
			-- Bytes resident in physical memory.
		require
			memory_available: memory_status = {TM_READING_STATUS}.Available
		do
			Result := stored_working_set
		end

	private_bytes: INTEGER_64
			-- Bytes committed privately.
		require
			memory_available: memory_status = {TM_READING_STATUS}.Available
		do
			Result := stored_private_bytes
		end

	handles: INTEGER
			-- Open handle count.
		require
			memory_available: memory_status = {TM_READING_STATUS}.Available
		do
			Result := stored_handles
		end

	read_bytes: INTEGER_64
			-- Cumulative bytes read, all IO.
		require
			io_available: io_status = {TM_READING_STATUS}.Available
		do
			Result := stored_read_bytes
		end

	write_bytes: INTEGER_64
			-- Cumulative bytes written, all IO.
		require
			io_available: io_status = {TM_READING_STATUS}.Available
		do
			Result := stored_write_bytes
		end

feature -- Element change

	set_cpu (a_user_ticks, a_kernel_ticks: INTEGER_64)
			-- Record cumulative CPU times.
		require
			not_yet: cpu_status = {TM_READING_STATUS}.Unavailable
			non_negative: a_user_ticks >= 0 and a_kernel_ticks >= 0
		do
			stored_user_ticks := a_user_ticks
			stored_kernel_ticks := a_kernel_ticks
			cpu_status := {TM_READING_STATUS}.Available
		ensure
			available: cpu_status = {TM_READING_STATUS}.Available
			kept: user_ticks = a_user_ticks and kernel_ticks = a_kernel_ticks
			others_unchanged: memory_status = old memory_status and io_status = old io_status
		end

	deny_cpu (a_status: INTEGER)
			-- Record why there are no CPU times.
		require
			not_yet: cpu_status = {TM_READING_STATUS}.Unavailable
			a_reason: a_status >= {TM_READING_STATUS}.Not_supported and a_status <= {TM_READING_STATUS}.Invalid
		do
			cpu_status := a_status
		ensure
			kept: cpu_status = a_status
			others_unchanged: memory_status = old memory_status and io_status = old io_status
		end

	set_memory (a_working_set, a_private_bytes: INTEGER_64; a_handles: INTEGER)
			-- Record memory gauges and handle count.
		require
			not_yet: memory_status = {TM_READING_STATUS}.Unavailable
			non_negative: a_working_set >= 0 and a_private_bytes >= 0 and a_handles >= 0
		do
			stored_working_set := a_working_set
			stored_private_bytes := a_private_bytes
			stored_handles := a_handles
			memory_status := {TM_READING_STATUS}.Available
		ensure
			available: memory_status = {TM_READING_STATUS}.Available
			kept: working_set = a_working_set and private_bytes = a_private_bytes and handles = a_handles
			others_unchanged: cpu_status = old cpu_status and io_status = old io_status
		end

	deny_memory (a_status: INTEGER)
			-- Record why there are no memory gauges.
		require
			not_yet: memory_status = {TM_READING_STATUS}.Unavailable
			a_reason: a_status >= {TM_READING_STATUS}.Not_supported and a_status <= {TM_READING_STATUS}.Invalid
		do
			memory_status := a_status
		ensure
			kept: memory_status = a_status
			others_unchanged: cpu_status = old cpu_status and io_status = old io_status
		end

	set_io (a_read_bytes, a_write_bytes: INTEGER_64)
			-- Record cumulative IO byte counts.
		require
			not_yet: io_status = {TM_READING_STATUS}.Unavailable
			non_negative: a_read_bytes >= 0 and a_write_bytes >= 0
		do
			stored_read_bytes := a_read_bytes
			stored_write_bytes := a_write_bytes
			io_status := {TM_READING_STATUS}.Available
		ensure
			available: io_status = {TM_READING_STATUS}.Available
			kept: read_bytes = a_read_bytes and write_bytes = a_write_bytes
			others_unchanged: cpu_status = old cpu_status and memory_status = old memory_status
		end

	deny_io (a_status: INTEGER)
			-- Record why there are no IO counts.
		require
			not_yet: io_status = {TM_READING_STATUS}.Unavailable
			a_reason: a_status >= {TM_READING_STATUS}.Not_supported and a_status <= {TM_READING_STATUS}.Invalid
		do
			io_status := a_status
		ensure
			kept: io_status = a_status
			others_unchanged: cpu_status = old cpu_status and memory_status = old memory_status
		end

feature {NONE} -- Implementation

	stored_user_ticks, stored_kernel_ticks: INTEGER_64
	stored_working_set, stored_private_bytes: INTEGER_64
	stored_handles: INTEGER
	stored_read_bytes, stored_write_bytes: INTEGER_64

invariant
	parent_non_negative: parent_pid >= 0
	threads_non_negative: threads >= 0
	cpu_status_known: cpu_status >= {TM_READING_STATUS}.Available and cpu_status <= {TM_READING_STATUS}.Invalid
	memory_status_known: memory_status >= {TM_READING_STATUS}.Available and memory_status <= {TM_READING_STATUS}.Invalid
	io_status_known: io_status >= {TM_READING_STATUS}.Available and io_status <= {TM_READING_STATUS}.Invalid
	cpu_zero_unless_set: cpu_status /= {TM_READING_STATUS}.Available implies (stored_user_ticks = 0 and stored_kernel_ticks = 0)
	io_zero_unless_set: io_status /= {TM_READING_STATUS}.Available implies (stored_read_bytes = 0 and stored_write_bytes = 0)
	memory_zero_unless_set: memory_status /= {TM_READING_STATUS}.Available implies
		(stored_working_set = 0 and stored_private_bytes = 0 and stored_handles = 0)

end
