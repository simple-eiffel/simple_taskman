note
	description: "[
		The selected process, as Task Manager's Details tab knows it: path,
		command line, user, elevation, architecture, priority, efficiency
		mode, window title, and whether Windows considers it hung. A field
		that could not be read says why. Labels are made once; only their
		text changes (A-108).
	]"
	author: "Larry Rix"

class
	TM_DETAILS_VIEW

create
	make

feature {NONE} -- Initialization

	make
			-- Panel waiting for a selection.
		do
			create group.make_titled ("Selected process")
			create lines.make (Line_count)
			from until lines.count = Line_count loop
				lines.extend (create {SW_LABEL}.make_ui (""))
				group.put (lines.last)
			end
			clear
		end

feature -- Access

	group: SW_GROUP
			-- The panel widget.

	Line_count: INTEGER = 10

feature -- Element change

	clear
			-- Nothing selected.
		do
			lines [1].set_text ({STRING_32} "Select a process in the list to see its details and act on it.")
			from lines.go_i_th (2) until lines.after loop
				lines.item.set_text ("")
				lines.forth
			end
		end

	show (a_name: READABLE_STRING_32; a_details: TM_PROCESS_DETAILS; a_windows: TM_WINDOW_INDEX)
			-- Details of `a_name' (`a_details').
		local
			l_priority: TM_PRIORITY
			l_format: TM_FORMAT
		do
			create l_priority
			create l_format
			lines [1].set_text (a_name + {STRING_32} "   PID " + a_details.id.pid.out.to_string_32)
			if a_details.is_gone then
				lines [2].set_text ({STRING_32} "This process has ended.")
				from lines.go_i_th (3) until lines.after loop
					lines.item.set_text ("")
					lines.forth
				end
			else
				lines [2].set_text (field ({STRING_32} "Path", a_details.image_path, a_details.path_status, l_format))
				lines [3].set_text (field ({STRING_32} "Command line", a_details.command_line, a_details.command_line_status, l_format))
				lines [4].set_text (field ({STRING_32} "User", a_details.user_name, a_details.user_status, l_format))
				lines [5].set_text (field ({STRING_32} "Elevated", yes_no (a_details.is_elevated), a_details.elevation_status, l_format))
				lines [6].set_text (field ({STRING_32} "Architecture", a_details.architecture, a_details.architecture_status, l_format))
				if a_details.priority_status = {TM_READING_STATUS}.Available then
					lines [7].set_text (field ({STRING_32} "Priority", l_priority.name (a_details.priority_class), a_details.priority_status, l_format))
				else
					lines [7].set_text (field ({STRING_32} "Priority", {STRING_32} "", a_details.priority_status, l_format))
				end
				lines [8].set_text (field ({STRING_32} "Efficiency mode", on_off (a_details.is_efficiency_mode), a_details.efficiency_status, l_format))
				if a_windows.has_window (a_details.id.pid) then
					lines [9].set_text ({STRING_32} "Window: " + a_windows.main_title (a_details.id.pid))
					if a_windows.is_hung (a_details.id.pid) then
						lines [10].set_text ({STRING_32} "Status: Not responding")
					else
						lines [10].set_text ({STRING_32} "Status: responding")
					end
				else
					lines [9].set_text ({STRING_32} "Window: none (a background process)")
					lines [10].set_text ("")
				end
				if a_details.critical_status = {TM_READING_STATUS}.Available and then a_details.is_critical then
					lines [10].set_text ({STRING_32} "Windows marks this process critical: it cannot be ended.")
				end
			end
		end

feature {NONE} -- Implementation

	lines: ARRAYED_LIST [SW_LABEL]

	field (a_label, a_value: READABLE_STRING_32; a_status: INTEGER; a_format: TM_FORMAT): STRING_32
			-- "Label: value", or "Label: <reason>" when not read.
		do
			if a_status = {TM_READING_STATUS}.Available then
				Result := a_label + {STRING_32} ": " + a_value
			else
				Result := a_label + {STRING_32} ": " + a_format.status_word (a_status)
			end
		end

	yes_no (a_flag: BOOLEAN): STRING_32
		do
			if a_flag then
				Result := {STRING_32} "yes"
			else
				Result := {STRING_32} "no"
			end
		end

	on_off (a_flag: BOOLEAN): STRING_32
		do
			if a_flag then
				Result := {STRING_32} "on"
			else
				Result := {STRING_32} "off"
			end
		end

invariant
	ten_lines: lines.count = Line_count

end
