note
	description: "[
		The owner's choices, kept in %LOCALAPPDATA%\simple_taskman\settings.toml
		(simple_toml): update speed, paused, always on top, the page the
		window opens on, recording, and recording at logon. A missing or
		unreadable file leaves the defaults and says why in `last_error';
		nothing is raised.
	]"
	author: "Larry Rix"

class
	TM_SETTINGS

create
	make

feature {NONE} -- Initialization

	make
			-- Defaults: normal speed, live, not on top, Processes page, recording on, not at logon.
		do
			update_ms := Normal_ms
			start_page := {STRING_32} "processes"
			records := True
			create last_error.make_empty
		ensure
			defaults: update_ms = Normal_ms and not is_paused and not is_always_on_top and records and not records_at_logon
		end

feature -- Access

	update_ms: INTEGER
			-- Sampling interval: High_ms, Normal_ms, or Low_ms.

	start_page: STRING_32
			-- Main tab opened at start (lower case label).

	last_error: STRING_32
			-- Why the last load or save failed; empty after a success.

	High_ms: INTEGER = 500
	Normal_ms: INTEGER = 1000
	Low_ms: INTEGER = 4000

feature -- Status report

	is_paused: BOOLEAN
			-- Is the display frozen (recording goes on)?

	is_always_on_top: BOOLEAN

	records: BOOLEAN
			-- Does the window record history?

	records_at_logon: BOOLEAN
			-- Does the background recorder start at logon?

	is_valid_speed (a_ms: INTEGER): BOOLEAN
		do
			Result := a_ms = High_ms or a_ms = Normal_ms or a_ms = Low_ms
		end

feature -- Element change

	set_update_ms (a_ms: INTEGER)
		require
			valid: is_valid_speed (a_ms)
		do
			update_ms := a_ms
		ensure
			set: update_ms = a_ms
		end

	set_paused (a_paused: BOOLEAN)
		do
			is_paused := a_paused
		ensure
			set: is_paused = a_paused
		end

	set_always_on_top (a_on: BOOLEAN)
		do
			is_always_on_top := a_on
		ensure
			set: is_always_on_top = a_on
		end

	set_start_page (a_page: READABLE_STRING_32)
		require
			named: not a_page.is_empty
		do
			start_page := a_page.as_lower
		ensure
			set: start_page.same_string (a_page.as_lower)
		end

	set_records (a_on: BOOLEAN)
		do
			records := a_on
		ensure
			set: records = a_on
		end

	set_records_at_logon (a_on: BOOLEAN)
		do
			records_at_logon := a_on
		ensure
			set: records_at_logon = a_on
		end

feature -- Persistence

	load (a_path: READABLE_STRING_32)
			-- Read `a_path'; keep the current values for anything missing or wrong.
		local
			l_toml: SIMPLE_TOML
			l_failed: BOOLEAN
			l_ms: INTEGER_64
		do
			last_error.wipe_out
			if l_failed then
				last_error.append ({STRING_32} "settings could not be read: " + a_path)
			elseif not (create {RAW_FILE}.make_with_name (a_path)).exists then
				last_error.append ({STRING_32} "no settings file yet: " + a_path)
			else
				create l_toml
				if attached l_toml.load_file (a_path.to_string_32) as al_table then
					if al_table.has ({STRING_32} "update_ms") then
						l_ms := al_table.integer_item ({STRING_32} "update_ms")
						if l_ms >= 1 and l_ms <= 100_000 and then is_valid_speed (l_ms.to_integer_32) then
							update_ms := l_ms.to_integer_32
						end
					end
					if al_table.has ({STRING_32} "paused") then
						is_paused := al_table.boolean_item ({STRING_32} "paused")
					end
					if al_table.has ({STRING_32} "always_on_top") then
						is_always_on_top := al_table.boolean_item ({STRING_32} "always_on_top")
					end
					if al_table.has ({STRING_32} "records") then
						records := al_table.boolean_item ({STRING_32} "records")
					end
					if al_table.has ({STRING_32} "records_at_logon") then
						records_at_logon := al_table.boolean_item ({STRING_32} "records_at_logon")
					end
					if attached al_table.string_item ({STRING_32} "start_page") as al_page and then not al_page.is_empty then
						start_page := al_page.as_lower
					end
				else
					last_error.append ({STRING_32} "settings file is not valid TOML: " + a_path)
				end
			end
		ensure
			speed_valid: is_valid_speed (update_ms)
		rescue
			l_failed := True
			retry
		end

	save (a_path: READABLE_STRING_32)
			-- Write the settings to `a_path', creating its folder.
		local
			l_toml: SIMPLE_TOML
			l_table: TOML_TABLE
			l_failed: BOOLEAN
			l_folder: DIRECTORY
			l_cut: INTEGER
		do
			last_error.wipe_out
			if l_failed then
				last_error.append ({STRING_32} "settings could not be saved: " + a_path)
			else
				l_cut := a_path.last_index_of ({CHARACTER_32} '\', a_path.count)
				if l_cut > 1 then
					create l_folder.make_with_name (a_path.substring (1, l_cut - 1))
					if not l_folder.exists then
						l_folder.recursive_create_dir
					end
				end
				create l_toml
				l_table := l_toml.table
				l_table.put (l_toml.integer_value (update_ms), {STRING_32} "update_ms")
				l_table.put (l_toml.boolean_value (is_paused), {STRING_32} "paused")
				l_table.put (l_toml.boolean_value (is_always_on_top), {STRING_32} "always_on_top")
				l_table.put (l_toml.string_value (start_page), {STRING_32} "start_page")
				l_table.put (l_toml.boolean_value (records), {STRING_32} "records")
				l_table.put (l_toml.boolean_value (records_at_logon), {STRING_32} "records_at_logon")
				l_toml.save_file (l_table, a_path.to_string_32)
			end
		rescue
			l_failed := True
			retry
		end

invariant
	speed_valid: is_valid_speed (update_ms)
	page_named: not start_page.is_empty

end
