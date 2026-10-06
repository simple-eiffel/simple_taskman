note
	description: "[
		The Settings page: update speed (High, Normal, Low, Paused), always on
		top, the page the window opens on, and whether the window records.
		Each change is applied at once by the window (through `on_change') and
		saved. Later slices add recording at logon, restart as administrator,
		and opening on Ctrl+Shift+Esc.
	]"
	author: "Larry Rix"

class
	TM_SETTINGS_VIEW

create
	make

feature {NONE} -- Initialization

	make (a_settings: TM_SETTINGS; a_pages: ARRAY [STRING_32])
			-- Page editing `a_settings'; `a_pages' are the main tab labels.
		local
			l_row: SW_ROW
		do
			settings := a_settings
			create pages.make_from_array (a_pages)
			create column.make
			column := column.with_padding (12.0).with_gap (16.0)
			create speed.make
			across <<"High (0.5 s)", "Normal (1 s)", "Low (4 s)", "Paused">> as ic loop
				speed.add_segment (ic)
			end
			create page_choice.make
			across a_pages as ic loop
				page_choice.add_segment (ic)
			end
			create on_top.make ("Always on top", a_settings.is_always_on_top, Void)
			create recording.make ("Record history (from the next start)", a_settings.records, Void)
			create at_logon.make ("Record from logon (background recorder, keeps recording after the window closes)", a_settings.records_at_logon, Void)
			create note_label.make_ui ("")
			column.put (labelled ("Update speed", speed))
			column.put (labelled ("Open on", page_choice))
			column.put (on_top)
			column.put (recording)
			column.put (at_logon)
			column.put (note_label)
			create extras.make
			extras := extras.with_gap (12.0)
			create admin_label.make_ui ("")
			create admin_button.make ("Restart as administrator", Void)
			admin_button := admin_button.with_max_size (260.0, 0.0)
			create ctrl_shift_esc.make ("Open simple_taskman on Ctrl+Shift+Esc (needs administrator; turn off before uninstalling)", False, Void)
			extras.put (admin_label)
			extras.put (admin_button)
			extras.put (ctrl_shift_esc)
			column.put (extras)
			create l_row.make
			show_settings
			speed.set_on_change (agent speed_changed)
			page_choice.set_on_change (agent page_changed)
			on_top.set_on_change (agent switch_changed)
			recording.set_on_change (agent switch_changed)
			at_logon.set_on_change (agent switch_changed)
			admin_button.set_on_click (agent admin_clicked)
			ctrl_shift_esc.set_on_change (agent ctrl_shift_esc_changed)
		end

feature -- Access

	column: SW_COLUMN
			-- The page widget.

	extras: SW_COLUMN
			-- Room for the later slices' controls.

	settings: TM_SETTINGS

feature -- Element change

	set_on_change (a_action: PROCEDURE)
			-- Call `a_action' after any change.
		do
			on_change := a_action
		end

	set_admin_state (a_elevated, a_ctrl_shift_esc: BOOLEAN)
			-- Show whether this window has administrator rights and where Ctrl+Shift+Esc goes.
		do
			if a_elevated then
				admin_label.set_text ({STRING_32} "Running as administrator: every process, service, and user can be acted on.")
			else
				admin_label.set_text ({STRING_32} "Not running as administrator: some actions are refused, and say so.")
			end
			quiet := True
			ctrl_shift_esc.set_on (a_ctrl_shift_esc)
			quiet := False
		end

	set_admin_actions (a_restart: PROCEDURE; a_ctrl_shift_esc: PROCEDURE [BOOLEAN])
			-- Call `a_restart' for the button and `a_ctrl_shift_esc' when the switch moves.
		do
			restart_action := a_restart
			ctrl_shift_esc_action := a_ctrl_shift_esc
		end

	set_note (a_text: READABLE_STRING_GENERAL)
		do
			note_label.set_text (a_text)
		end

feature {NONE} -- Implementation

	pages: ARRAYED_LIST [STRING_32]
	speed, page_choice: SW_SEGMENTED
	on_top, recording, at_logon, ctrl_shift_esc: SW_SWITCH
	admin_label: SW_LABEL
	admin_button: SW_BUTTON
	restart_action: detachable PROCEDURE
	ctrl_shift_esc_action: detachable PROCEDURE [BOOLEAN]
	quiet: BOOLEAN
			-- Set while the window itself moves a control, so no handler runs.

	admin_clicked
		do
			if attached restart_action as al_action then
				al_action.call (Void)
			end
		end

	ctrl_shift_esc_changed
		do
			if not quiet and attached ctrl_shift_esc_action as al_action then
				al_action.call ([ctrl_shift_esc.is_on])
			end
		end
	note_label: SW_LABEL
	on_change: detachable PROCEDURE

	labelled (a_label: READABLE_STRING_GENERAL; a_widget: SW_WIDGET): SW_ROW
		do
			create Result.make
			Result := Result.with_gap (16.0)
			Result.put ((create {SW_LABEL}.make_ui (a_label)).with_min_size (140.0, 0.0).with_max_size (140.0, 0.0))
			Result.put (a_widget)
		end

	show_settings
			-- Controls from `settings'.
		do
			if settings.is_paused then
				speed.select_segment (4)
			elseif settings.update_ms = settings.High_ms then
				speed.select_segment (1)
			elseif settings.update_ms = settings.Low_ms then
				speed.select_segment (3)
			else
				speed.select_segment (2)
			end
			across pages as ic loop
				if ic.as_lower.same_string (settings.start_page) then
					page_choice.select_segment (@ic.cursor_index)
				end
			end
		end

	speed_changed (a_index: INTEGER)
		do
			inspect a_index
			when 1 then
				settings.set_paused (False)
				settings.set_update_ms (settings.High_ms)
			when 3 then
				settings.set_paused (False)
				settings.set_update_ms (settings.Low_ms)
			when 4 then
				settings.set_paused (True)
			else
				settings.set_paused (False)
				settings.set_update_ms (settings.Normal_ms)
			end
			changed
		end

	page_changed (a_index: INTEGER)
		do
			if a_index >= 1 and a_index <= pages.count then
				settings.set_start_page (pages [a_index])
			end
			changed
		end

	switch_changed
		do
			settings.set_always_on_top (on_top.is_on)
			settings.set_records (recording.is_on)
			settings.set_records_at_logon (at_logon.is_on)
			changed
		end

	changed
		do
			if attached on_change as al_action then
				al_action.call (Void)
			end
		end

end
