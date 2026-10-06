note
	description: "[
		The visible top-level windows and the processes that own them: what
		makes a process an "app" in Task Manager's grouping, the title shown
		for it, and whether Windows considers it hung ("Not responding",
		IsHungAppWindow). Walks GetTopWindow/GetWindow(GW_HWNDNEXT);
		GetWindowTextW reads a caption without sending a message, so a hung
		window cannot stall the walk. `refresh' is the only command.
	]"
	author: "Larry Rix"

class
	TM_WINDOW_INDEX

create
	make

feature {NONE} -- Initialization

	make
			-- Empty index; `refresh' fills it.
		do
			create table.make (64)
		ensure
			empty: window_count = 0
		end

feature -- Access

	window_count: INTEGER
			-- Windows found by the last `refresh'.

	main_title (a_pid: INTEGER_64): STRING_32
			-- Title of `a_pid''s first window.
		require
			has: has_window (a_pid)
		do
			if attached table.item (a_pid) as al_list and then not al_list.is_empty then
				Result := al_list.first.title
			else
				create Result.make_empty
			end
		end

	handles (a_pid: INTEGER_64): ARRAYED_LIST [POINTER]
			-- `a_pid''s top-level windows.
		do
			create Result.make (2)
			if attached table.item (a_pid) as al_list then
				across al_list as ic loop
					Result.extend (ic.handle)
				end
			end
		ensure
			none_without_window: not has_window (a_pid) implies Result.is_empty
		end

feature -- Status report

	has_window (a_pid: INTEGER_64): BOOLEAN
			-- Does `a_pid' own a visible top-level window?
		do
			Result := table.has (a_pid)
		end

	is_hung (a_pid: INTEGER_64): BOOLEAN
			-- Does Windows consider one of `a_pid''s windows hung?
		do
			if attached table.item (a_pid) as al_list then
				Result := across al_list as ic some ic.hung end
			end
		ensure
			only_with_window: Result implies has_window (a_pid)
		end

feature -- Element change

	refresh
			-- List the visible, unowned, non-tool top-level windows that have a title.
		local
			l_buffer: MANAGED_POINTER
			l_count, i, l_length, j: INTEGER
			l_base: INTEGER
			l_pid: INTEGER_64
			l_title: STRING_32
			l_list: ARRAYED_LIST [TUPLE [handle: POINTER; title: STRING_32; hung: BOOLEAN]]
		do
			create l_buffer.make (Entry_size * Max_windows)
			l_count := c_windows (l_buffer.item, Max_windows)
			table.wipe_out
			from i := 0 until i = l_count loop
				l_base := i * Entry_size
				l_pid := l_buffer.read_natural_32 (l_base).to_integer_64
				l_length := l_buffer.read_integer_32 (l_base + 16).max (0).min (Title_chars)
				create l_title.make (l_length)
				from j := 0 until j = l_length loop
					l_title.append_code (l_buffer.read_natural_16 (l_base + 24 + j * 2).to_natural_32)
					j := j + 1
				end
				if attached table.item (l_pid) as al_list then
					l_list := al_list
				else
					create l_list.make (2)
					table.force (l_list, l_pid)
				end
				l_list.extend ([l_buffer.read_pointer (l_base + 8), l_title, l_buffer.read_integer_32 (l_base + 20) /= 0])
				i := i + 1
			end
			window_count := l_count
		ensure
			counted: window_count >= 0 and window_count <= Max_windows
		end

feature -- Constants

	Max_windows: INTEGER = 1024
	Title_chars: INTEGER = 127
	Entry_size: INTEGER = 280
			-- pid (4) + pad (4) + hwnd (8) + length (4) + hung (4) + 128 UTF-16 units (256).

feature {NONE} -- Implementation

	table: HASH_TABLE [ARRAYED_LIST [TUPLE [handle: POINTER; title: STRING_32; hung: BOOLEAN]], INTEGER_64]
			-- Windows by owning pid.

	c_windows (a_buffer: POINTER; a_max: INTEGER): INTEGER
			-- Fill `a_buffer' with up to `a_max' entries; their number.
		external
			"C inline use <windows.h>"
		alias
			"[
				int l_count = 0;
				HWND l_window = GetTopWindow (NULL);
				while (l_window != NULL && l_count < $a_max) {
					if (IsWindowVisible (l_window) && GetWindow (l_window, GW_OWNER) == NULL
							&& !(GetWindowLongPtrW (l_window, GWL_EXSTYLE) & WS_EX_TOOLWINDOW)
							&& GetWindowTextLengthW (l_window) > 0) {
						BYTE *l_entry = ((BYTE *) $a_buffer) + l_count * 280;
						DWORD l_pid = 0;
						int l_length;
						GetWindowThreadProcessId (l_window, &l_pid);
						*((DWORD *) l_entry) = l_pid;
						*((HWND *) (l_entry + 8)) = l_window;
						l_length = GetWindowTextW (l_window, (LPWSTR) (l_entry + 24), 128);
						*((int *) (l_entry + 16)) = (l_length < 0) ? 0 : l_length;
						*((int *) (l_entry + 20)) = IsHungAppWindow (l_window) ? 1 : 0;
						l_count++;
					}
					l_window = GetWindow (l_window, GW_HWNDNEXT);
				}
				return (EIF_INTEGER) l_count;
			]"
		end

invariant
	counted: window_count >= 0

end
