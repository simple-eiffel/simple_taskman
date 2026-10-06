note
	description: "[
		Apps Windows starts at logon, from the places Task Manager reads:
		the Run keys (yours, all users', all users' 32-bit) and the Startup
		folders (yours, all users'). Enabled or disabled comes from Explorer's
		StartupApproved values (first byte even: enabled; odd: disabled;
		absent: enabled), which is also how `set_enabled' turns an app off
		without deleting it, exactly as Task Manager does. Changing an
		all-users entry needs administrator rights; the result says so.
		The publisher is the file's CompanyName (version.dll, loaded on use).
	]"
	author: "Larry Rix"

class
	TM_STARTUP_LIST

create
	make

feature {NONE} -- Initialization

	make
			-- Empty list; `refresh' fills it.
		do
			create items.make (32)
		ensure
			empty: items.is_empty
		end

feature -- Access

	items: ARRAYED_LIST [TM_STARTUP_ITEM]

feature -- Element change

	refresh
			-- Read the Run keys and Startup folders again.
		local
			l_env: SIMPLE_ENV
		do
			items.wipe_out
			read_run_key (1, 1, {STRING_32} "Registry (you)")
			read_run_key (2, 1, {STRING_32} "Registry (all users)")
			read_run_key (2, 2, {STRING_32} "Registry (all users, 32-bit)")
			create l_env
			if attached l_env.item ("APPDATA") as al_appdata then
				read_folder (al_appdata + {STRING_32} "\Microsoft\Windows\Start Menu\Programs\Startup", 1, {STRING_32} "Startup folder (you)")
			end
			if attached l_env.item ("ProgramData") as al_data then
				read_folder (al_data + {STRING_32} "\Microsoft\Windows\Start Menu\Programs\StartUp", 2, {STRING_32} "Startup folder (all users)")
			end
			across items as ic loop
				ic.set_publisher (company_of (ic.image_path))
			end
		end

	set_enabled (a_item: TM_STARTUP_ITEM; a_on: BOOLEAN): TM_ACTION_RESULT
			-- Turn `a_item' on or off through StartupApproved.
		local
			l_name: NATIVE_STRING
			l_error: INTEGER
			l_action: STRING_32
		do
			if a_on then
				l_action := {STRING_32} "Enable " + a_item.name
			else
				l_action := {STRING_32} "Disable " + a_item.name
			end
			create l_name.make (a_item.name)
			l_error := c_set_approved (a_item.root, a_item.kind, l_name.item, a_on)
			inspect l_error
			when 0 then
				create Result.make_done (l_action, 0)
			when 5 then
				create Result.make_refused (l_action, {STRING_32} "access denied (an all-users entry: run as administrator)")
			else
				create Result.make_refused (l_action, {STRING_32} "Windows error " + l_error.out.to_string_32)
			end
		end

feature {NONE} -- Reading

	read_run_key (a_root, a_kind: INTEGER; a_where: STRING_32)
			-- Entries of one Run key.
		local
			l_buffer: MANAGED_POINTER
			l_count, i, l_base: INTEGER
			l_name, l_command: STRING_32
		do
			create l_buffer.make (Entry_size * Max_entries)
			l_count := c_read_run (a_root, a_kind, l_buffer.item, Max_entries)
			from i := 0 until i >= l_count loop
				l_base := i * Entry_size
				l_name := wide (l_buffer, l_base, l_buffer.read_integer_32 (l_base + 1280).max (0).min (127))
				l_command := wide (l_buffer, l_base + 256, l_buffer.read_integer_32 (l_base + 1284).max (0).min (511))
				if not l_name.is_empty then
					items.extend (create {TM_STARTUP_ITEM}.make (l_name, l_command, image_of (l_command), a_where,
						a_root, a_kind, approved (a_root, a_kind, l_name)))
				end
				i := i + 1
			end
		end

	read_folder (a_folder: STRING_32; a_root: INTEGER; a_where: STRING_32)
			-- Shortcuts and programs in one Startup folder.
		local
			l_directory: DIRECTORY
			l_name: STRING_32
		do
			create l_directory.make_with_name (a_folder)
			if l_directory.exists then
				across l_directory.entries as ic loop
					l_name := ic.name
					if not l_name.same_string ({STRING_32} ".") and not l_name.same_string ({STRING_32} "..")
							and not l_name.is_case_insensitive_equal ({STRING_32} "desktop.ini") then
						items.extend (create {TM_STARTUP_ITEM}.make (l_name, a_folder + {STRING_32} "\" + l_name,
							a_folder + {STRING_32} "\" + l_name, a_where, a_root, 3, approved (a_root, 3, l_name)))
					end
				end
			end
		end

	approved (a_root, a_kind: INTEGER; a_name: STRING_32): BOOLEAN
			-- Is the entry enabled according to StartupApproved (absent means enabled)?
		local
			l_name: NATIVE_STRING
		do
			create l_name.make (a_name)
			Result := c_approved (a_root, a_kind, l_name.item) /= 0
		end

	image_of (a_command: STRING_32): STRING_32
			-- The program file a Run command starts, with %VARIABLES% expanded.
		local
			l_text: STRING_32
			l_end: INTEGER
		do
			l_text := expanded_command (a_command)
			l_text.left_adjust
			if l_text.starts_with ({STRING_32} "%"") then
				l_end := l_text.index_of ('"', 2)
				if l_end > 2 then
					Result := l_text.substring (2, l_end - 1)
				else
					Result := l_text.substring (2, l_text.count)
				end
			else
				l_end := l_text.as_lower.substring_index ({STRING_32} ".exe", 1)
				if l_end > 0 then
					Result := l_text.substring (1, l_end + 3)
				else
					l_end := l_text.index_of (' ', 1)
					if l_end > 1 then
						Result := l_text.substring (1, l_end - 1)
					else
						Result := l_text
					end
				end
			end
		end

	expanded_command (a_command: STRING_32): STRING_32
			-- `a_command' with each %NAME% replaced by its environment value.
		local
			l_env: SIMPLE_ENV
			i, l_close: INTEGER
		do
			create Result.make (a_command.count)
			create l_env
			from i := 1 until i > a_command.count loop
				if a_command [i] = '%%' then
					l_close := a_command.index_of ('%%', i + 1)
					if l_close > i + 1 and then attached l_env.item (a_command.substring (i + 1, l_close - 1)) as al_value then
						Result.append (al_value)
						i := l_close + 1
					else
						Result.append_character (a_command [i])
						i := i + 1
					end
				else
					Result.append_character (a_command [i])
					i := i + 1
				end
			end
		end

	company_of (a_path: STRING_32): STRING_32
			-- CompanyName in the file's version resource; empty when none.
		local
			l_path: NATIVE_STRING
			l_buffer: MANAGED_POINTER
			l_count: INTEGER
		do
			create Result.make_empty
			if not a_path.is_empty and then a_path.as_lower.ends_with ({STRING_32} ".exe") then
				create l_path.make (a_path)
				create l_buffer.make (512)
				l_count := c_company (l_path.item, l_buffer.item, 255)
				if l_count > 0 then
					Result := wide (l_buffer, 0, l_count)
					Result.right_adjust
				end
			end
		end

	wide (a_buffer: MANAGED_POINTER; a_offset, a_count: INTEGER): STRING_32
		require
			fits: a_offset >= 0 and a_count >= 0 and a_offset + a_count * 2 <= a_buffer.count
		local
			i: INTEGER
		do
			create Result.make (a_count)
			from i := 0 until i = a_count loop
				Result.append_code (a_buffer.read_natural_16 (a_offset + i * 2).to_natural_32)
				i := i + 1
			end
		end

	Max_entries: INTEGER = 256
	Entry_size: INTEGER = 1296
			-- name (128 UTF-16) + command (512 UTF-16) + two lengths, padded.

feature {NONE} -- Externals

	c_read_run (a_root, a_kind: INTEGER; a_buffer: POINTER; a_max: INTEGER): INTEGER
			-- Values of a Run key (root 1 HKCU, 2 HKLM; kind 2 = 32-bit view) into entries; their number.
		external
			"C inline use <windows.h>"
		alias
			"[
				HKEY l_key;
				DWORD l_index = 0;
				int l_count = 0;
				REGSAM l_access = KEY_READ | (($a_kind == 2) ? KEY_WOW64_32KEY : KEY_WOW64_64KEY);
				HKEY l_root = ($a_root == 1) ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
				if (RegOpenKeyExW (l_root, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, l_access, &l_key) != ERROR_SUCCESS) return 0;
				while (l_count < $a_max) {
					WCHAR l_name [128];
					BYTE l_data [2048];
					DWORD l_name_size = 128, l_data_size = sizeof (l_data) - 2, l_type = 0;
					LONG l_status = RegEnumValueW (l_key, l_index, l_name, &l_name_size, NULL, &l_type, l_data, &l_data_size);
					if (l_status == ERROR_NO_MORE_ITEMS) break;
					l_index++;
					if (l_status != ERROR_SUCCESS) continue;
					if (l_type == REG_SZ || l_type == REG_EXPAND_SZ) {
						BYTE *l_entry = ((BYTE *) $a_buffer) + l_count * 1296;
						int l_command_length = (int) (l_data_size / 2);
						while (l_command_length > 0 && ((WCHAR *) l_data) [l_command_length - 1] == 0) l_command_length--;
						if (l_command_length > 511) l_command_length = 511;
						if (l_name_size > 127) l_name_size = 127;
						memcpy (l_entry, l_name, l_name_size * 2);
						memcpy (l_entry + 256, l_data, l_command_length * 2);
						*((int *) (l_entry + 1280)) = (int) l_name_size;
						*((int *) (l_entry + 1284)) = l_command_length;
						l_count++;
					}
				}
				RegCloseKey (l_key);
				return (EIF_INTEGER) l_count;
			]"
		end

	c_approved (a_root, a_kind: INTEGER; a_name: POINTER): INTEGER
			-- 1 enabled (or no StartupApproved value), 0 disabled.
		external
			"C inline use <windows.h>"
		alias
			"[
				HKEY l_key;
				BYTE l_data [16];
				DWORD l_size = sizeof (l_data), l_type = 0;
				const WCHAR *l_path = ($a_kind == 1) ? L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run"
					: (($a_kind == 2) ? L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run32"
					: L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\StartupFolder");
				HKEY l_root = ($a_root == 1) ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
				if (RegOpenKeyExW (l_root, l_path, 0, KEY_READ, &l_key) != ERROR_SUCCESS) return 1;
				if (RegQueryValueExW (l_key, (LPCWSTR) $a_name, NULL, &l_type, l_data, &l_size) != ERROR_SUCCESS || l_size < 1) {
					RegCloseKey (l_key); return 1;
				}
				RegCloseKey (l_key);
				return (l_data [0] & 1) ? 0 : 1;
			]"
		end

	c_set_approved (a_root, a_kind: INTEGER; a_name: POINTER; a_on: BOOLEAN): INTEGER
			-- Write the StartupApproved value (02 enabled, 03 disabled with the time); 0 or the Windows error.
		external
			"C inline use <windows.h>"
		alias
			"[
				HKEY l_key;
				BYTE l_data [12];
				FILETIME l_now;
				LONG l_status;
				const WCHAR *l_path = ($a_kind == 1) ? L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run"
					: (($a_kind == 2) ? L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run32"
					: L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\StartupFolder");
				HKEY l_root = ($a_root == 1) ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
				ZeroMemory (l_data, sizeof (l_data));
				l_data [0] = $a_on ? 2 : 3;
				if (!$a_on) { GetSystemTimeAsFileTime (&l_now); memcpy (l_data + 4, &l_now, 8); }
				l_status = RegCreateKeyExW (l_root, l_path, 0, NULL, 0, KEY_SET_VALUE, NULL, &l_key, NULL);
				if (l_status != ERROR_SUCCESS) return (EIF_INTEGER) l_status;
				l_status = RegSetValueExW (l_key, (LPCWSTR) $a_name, 0, REG_BINARY, l_data, sizeof (l_data));
				RegCloseKey (l_key);
				return (EIF_INTEGER) l_status;
			]"
		end

	c_company (a_path, a_buffer: POINTER; a_capacity: INTEGER): INTEGER
			-- CompanyName of the version resource of `a_path'; its length, 0 when none.
		external
			"C inline use <windows.h>"
		alias
			"[
				typedef DWORD (WINAPI *tm_size) (LPCWSTR, LPDWORD);
				typedef BOOL (WINAPI *tm_info) (LPCWSTR, DWORD, DWORD, LPVOID);
				typedef BOOL (WINAPI *tm_query) (LPCVOID, LPCWSTR, LPVOID *, PUINT);
				static HMODULE l_module = NULL;
				static tm_size l_size_of = NULL;
				static tm_info l_info_of = NULL;
				static tm_query l_query = NULL;
				DWORD l_handle = 0, l_size;
				BYTE *l_data;
				struct { WORD language; WORD codepage; } *l_translations;
				UINT l_length = 0;
				WCHAR l_key [64];
				LPWSTR l_text = NULL;
				int l_count = 0;
				if (l_module == NULL) {
					l_module = LoadLibraryW (L"version.dll");
					if (l_module == NULL) return 0;
					l_size_of = (tm_size) GetProcAddress (l_module, "GetFileVersionInfoSizeW");
					l_info_of = (tm_info) GetProcAddress (l_module, "GetFileVersionInfoW");
					l_query = (tm_query) GetProcAddress (l_module, "VerQueryValueW");
				}
				if (l_size_of == NULL || l_info_of == NULL || l_query == NULL) return 0;
				l_size = l_size_of ((LPCWSTR) $a_path, &l_handle);
				if (l_size == 0 || l_size > 1048576) return 0;
				l_data = (BYTE *) HeapAlloc (GetProcessHeap (), 0, l_size);
				if (l_data == NULL) return 0;
				if (l_info_of ((LPCWSTR) $a_path, 0, l_size, l_data)
						&& l_query (l_data, L"\\VarFileInfo\\Translation", (LPVOID *) &l_translations, &l_length) && l_length >= 4) {
					wsprintfW (l_key, L"\\StringFileInfo\\%04x%04x\\CompanyName", l_translations [0].language, l_translations [0].codepage);
					if (l_query (l_data, l_key, (LPVOID *) &l_text, &l_length) && l_text != NULL) {
						l_count = (int) wcslen (l_text);
						if (l_count > $a_capacity) l_count = $a_capacity;
						memcpy ((void *) $a_buffer, l_text, l_count * 2);
					}
				}
				HeapFree (GetProcessHeap (), 0, l_data);
				return (EIF_INTEGER) l_count;
			]"
		end

end
