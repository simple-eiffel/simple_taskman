note
	description: "[
		What Task Manager's Details tab knows about one process identity:
		image path, command line, user, elevation, architecture, priority
		class, efficiency mode, and whether Windows marks it critical. Every
		field has a status like a reading (TM_READING_STATUS): a field that
		could not be read says why, and is never shown as empty-but-fine.
		`is_gone' means the pid now belongs to another process or none.
	]"
	author: "Larry Rix"

class
	TM_PROCESS_DETAILS

create
	make

feature {NONE} -- Initialization

	make (a_id: TM_PROCESS_ID)
			-- Details of `a_id', every field unavailable until read.
		do
			id := a_id
			create image_path.make_empty
			create command_line.make_empty
			create user_name.make_empty
			create architecture.make_empty
			path_status := {TM_READING_STATUS}.Unavailable
			command_line_status := {TM_READING_STATUS}.Unavailable
			user_status := {TM_READING_STATUS}.Unavailable
			elevation_status := {TM_READING_STATUS}.Unavailable
			architecture_status := {TM_READING_STATUS}.Unavailable
			priority_status := {TM_READING_STATUS}.Unavailable
			efficiency_status := {TM_READING_STATUS}.Unavailable
			critical_status := {TM_READING_STATUS}.Unavailable
		ensure
			id_kept: id = a_id
			nothing_read: path_status = {TM_READING_STATUS}.Unavailable and not is_gone
		end

feature -- Access

	id: TM_PROCESS_ID

	image_path: STRING_32
	command_line: STRING_32
	user_name: STRING_32
			-- DOMAIN\user.
	architecture: STRING_32
			-- "x64", "x86", "ARM64".
	priority_class: INTEGER
			-- A TM_PRIORITY class when `priority_status' is available.

	path_status, command_line_status, user_status, elevation_status, architecture_status,
	priority_status, efficiency_status, critical_status: INTEGER
			-- TM_READING_STATUS of each field.

feature -- Status report

	is_elevated: BOOLEAN
			-- Running as administrator (when `elevation_status' is available)?

	is_efficiency_mode: BOOLEAN
			-- Execution-speed throttling on (when `efficiency_status' is available)?

	is_critical: BOOLEAN
			-- Does Windows stop if this process ends (when `critical_status' is available)?

	is_gone: BOOLEAN
			-- Did the identity end, or the pid pass to another process?

feature {TM_PROCESS_INSPECTOR} -- Element change

	set_image_path (a_path: READABLE_STRING_32)
		do
			create image_path.make_from_string (a_path)
			path_status := {TM_READING_STATUS}.Available
		ensure
			available: path_status = {TM_READING_STATUS}.Available and image_path.same_string (a_path)
		end

	set_command_line (a_text: READABLE_STRING_32)
		do
			create command_line.make_from_string (a_text)
			command_line_status := {TM_READING_STATUS}.Available
		ensure
			available: command_line_status = {TM_READING_STATUS}.Available
		end

	set_user_name (a_name: READABLE_STRING_32)
		do
			create user_name.make_from_string (a_name)
			user_status := {TM_READING_STATUS}.Available
		ensure
			available: user_status = {TM_READING_STATUS}.Available
		end

	set_elevated (a_elevated: BOOLEAN)
		do
			is_elevated := a_elevated
			elevation_status := {TM_READING_STATUS}.Available
		ensure
			available: elevation_status = {TM_READING_STATUS}.Available and is_elevated = a_elevated
		end

	set_architecture (a_name: READABLE_STRING_32)
		require
			named: not a_name.is_empty
		do
			create architecture.make_from_string (a_name)
			architecture_status := {TM_READING_STATUS}.Available
		ensure
			available: architecture_status = {TM_READING_STATUS}.Available
		end

	set_priority_class (a_class: INTEGER)
		require
			known: (create {TM_PRIORITY}).is_known (a_class)
		do
			priority_class := a_class
			priority_status := {TM_READING_STATUS}.Available
		ensure
			available: priority_status = {TM_READING_STATUS}.Available and priority_class = a_class
		end

	set_efficiency_mode (a_on: BOOLEAN)
		do
			is_efficiency_mode := a_on
			efficiency_status := {TM_READING_STATUS}.Available
		ensure
			available: efficiency_status = {TM_READING_STATUS}.Available
		end

	set_critical (a_critical: BOOLEAN)
		do
			is_critical := a_critical
			critical_status := {TM_READING_STATUS}.Available
		ensure
			available: critical_status = {TM_READING_STATUS}.Available
		end

	deny_all (a_status: INTEGER)
			-- Nothing could be read, for reason `a_status'.
		require
			not_available: a_status /= {TM_READING_STATUS}.Available
		do
			image_path.wipe_out
			command_line.wipe_out
			user_name.wipe_out
			architecture.wipe_out
			path_status := a_status
			command_line_status := a_status
			user_status := a_status
			elevation_status := a_status
			architecture_status := a_status
			priority_status := a_status
			efficiency_status := a_status
			critical_status := a_status
		end

	set_gone
			-- The identity ended or the pid was reused.
		do
			is_gone := True
			deny_all ({TM_READING_STATUS}.Unavailable)
		ensure
			gone: is_gone
		end

	deny_field (a_field, a_status: INTEGER)
			-- Field `a_field' (1 path .. 8 critical) could not be read, for reason `a_status'.
		require
			field_known: a_field >= 1 and a_field <= 8
			not_available: a_status /= {TM_READING_STATUS}.Available
		do
			inspect a_field
			when 1 then
				image_path.wipe_out
				path_status := a_status
			when 2 then command_line_status := a_status
			when 3 then user_status := a_status
			when 4 then elevation_status := a_status
			when 5 then architecture_status := a_status
			when 6 then priority_status := a_status
			when 7 then efficiency_status := a_status
			else critical_status := a_status
			end
		end

invariant
	path_only_when_read: path_status /= {TM_READING_STATUS}.Available implies image_path.is_empty
	priority_known_when_read: priority_status = {TM_READING_STATUS}.Available implies (create {TM_PRIORITY}).is_known (priority_class)
	gone_reads_nothing: is_gone implies path_status /= {TM_READING_STATUS}.Available

end
