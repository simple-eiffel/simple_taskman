note
	description: "[
		Facts about this machine that do not change while it runs, as Task
		Manager's Performance tab lists them: processor name and base speed
		(registry), sockets, cores, logical processors, cache sizes, firmware
		virtualization (GetLogicalProcessorInformationEx, IsProcessorFeature
		Present), installed memory, and display adapters. Read once at `make'.
		A fact that could not be read is empty or 0 and `has_*' says so.
		`uptime_seconds' is the one live query.
	]"
	author: "Larry Rix"

class
	TM_MACHINE_INFO

create
	make

feature {NONE} -- Initialization

	make
			-- Read every fact once.
		local
			l_buffer: MANAGED_POINTER
			l_numbers: MANAGED_POINTER
			l_count: INTEGER
		do
			create l_buffer.make (512)
			l_count := c_processor_name (l_buffer.item, 255)
			create processor_name.make (l_count)
			append_wide (processor_name, l_buffer, l_count)
			processor_name.adjust
			base_mhz := c_base_mhz
			create l_numbers.make (8 * 6)
			if c_topology (l_numbers.item) then
				sockets := l_numbers.read_integer_64 (0).to_integer_32
				cores := l_numbers.read_integer_64 (8).to_integer_32
				logical_processors := l_numbers.read_integer_64 (16).to_integer_32
				l1_bytes := l_numbers.read_integer_64 (24)
				l2_bytes := l_numbers.read_integer_64 (32)
				l3_bytes := l_numbers.read_integer_64 (40)
			end
			is_virtualization_enabled := c_virtualization
			installed_memory_bytes := c_installed_memory
			create display_adapters.make (2)
			read_display_adapters
		end

feature -- Access

	processor_name: STRING_32
	base_mhz: INTEGER
	sockets, cores, logical_processors: INTEGER
	l1_bytes, l2_bytes, l3_bytes: INTEGER_64
	installed_memory_bytes: INTEGER_64
			-- From the firmware's memory table; 0 when unknown.

	display_adapters: ARRAYED_LIST [STRING_32]
			-- Names of the display adapters, primary first, without repeats.

	uptime_seconds: INTEGER_64
			-- Seconds since Windows started.
		do
			Result := c_tick_count_64 // 1000
		ensure
			non_negative: Result >= 0
		end

	uptime_text: STRING_32
			-- "d:hh:mm:ss", as Task Manager shows uptime.
		local
			l_seconds: INTEGER_64
		do
			l_seconds := uptime_seconds
			Result := (l_seconds // 86_400).out.to_string_32 + {STRING_32} ":" + two ((l_seconds \\ 86_400) // 3_600)
				+ {STRING_32} ":" + two ((l_seconds \\ 3_600) // 60) + {STRING_32} ":" + two (l_seconds \\ 60)
		end

feature -- Status report

	is_virtualization_enabled: BOOLEAN
			-- Is hardware virtualization enabled in firmware?

	has_processor_name: BOOLEAN
		do
			Result := not processor_name.is_empty
		end

	has_topology: BOOLEAN
		do
			Result := logical_processors > 0
		end

feature {NONE} -- Implementation

	two (a_value: INTEGER_64): STRING_32
		do
			Result := a_value.out.to_string_32
			if Result.count < 2 then
				Result.prepend_character ('0')
			end
		end

	append_wide (a_target: STRING_32; a_buffer: MANAGED_POINTER; a_count: INTEGER)
			-- Append `a_count' UTF-16 units (no surrogates expected in these names).
		local
			i: INTEGER
		do
			from i := 0 until i >= a_count or i * 2 + 1 >= a_buffer.count loop
				a_target.append_code (a_buffer.read_natural_16 (i * 2).to_natural_32)
				i := i + 1
			end
		end

	read_display_adapters
			-- Adapter names from EnumDisplayDevicesW.
		local
			l_buffer: MANAGED_POINTER
			l_count, i: INTEGER
			l_name: STRING_32
		do
			create l_buffer.make (256)
			from i := 0 until i >= 16 loop
				l_count := c_display_device (i, l_buffer.item, 127)
				if l_count > 0 then
					create l_name.make (l_count)
					append_wide (l_name, l_buffer, l_count)
					l_name.adjust
					if not l_name.is_empty and then not across display_adapters as ic some ic.same_string (l_name) end then
						display_adapters.extend (l_name)
					end
				elseif l_count < 0 then
					i := 16
				end
				i := i + 1
			end
		end

feature {NONE} -- Externals

	c_processor_name (a_buffer: POINTER; a_capacity: INTEGER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"[
				DWORD l_size = (DWORD) ($a_capacity * 2);
				if (RegGetValueW (HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
						L"ProcessorNameString", RRF_RT_REG_SZ, NULL, (PVOID) $a_buffer, &l_size) != ERROR_SUCCESS) return 0;
				return (EIF_INTEGER) ((l_size / 2) > 0 ? (l_size / 2) - 1 : 0);
			]"
		end

	c_base_mhz: INTEGER
		external
			"C inline use <windows.h>"
		alias
			"[
				DWORD l_mhz = 0, l_size = sizeof (l_mhz);
				if (RegGetValueW (HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
						L"~MHz", RRF_RT_REG_DWORD, NULL, &l_mhz, &l_size) != ERROR_SUCCESS) return 0;
				return (EIF_INTEGER) l_mhz;
			]"
		end

	c_topology (a_out: POINTER): BOOLEAN
			-- Sockets, cores, logical processors, L1, L2, L3 bytes (six 64-bit integers).
		external
			"C inline use <windows.h>"
		alias
			"[
				DWORD l_length = 0;
				BYTE *l_raw, *l_cursor;
				EIF_INTEGER_64 *l_out = (EIF_INTEGER_64 *) $a_out;
				int i;
				for (i = 0; i < 6; i++) l_out [i] = 0;
				GetLogicalProcessorInformationEx (RelationAll, NULL, &l_length);
				if (l_length == 0) return EIF_FALSE;
				l_raw = (BYTE *) HeapAlloc (GetProcessHeap (), 0, l_length);
				if (l_raw == NULL) return EIF_FALSE;
				if (!GetLogicalProcessorInformationEx (RelationAll, (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX) l_raw, &l_length)) {
					HeapFree (GetProcessHeap (), 0, l_raw); return EIF_FALSE;
				}
				for (l_cursor = l_raw; l_cursor < l_raw + l_length; ) {
					PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX l_info = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX) l_cursor;
					if (l_info->Relationship == RelationProcessorPackage) {
						l_out [0]++;
					} else if (l_info->Relationship == RelationProcessorCore) {
						WORD g;
						l_out [1]++;
						for (g = 0; g < l_info->Processor.GroupCount; g++) {
							KAFFINITY m = l_info->Processor.GroupMask [g].Mask;
							while (m) { l_out [2] += (m & 1); m >>= 1; }
						}
					} else if (l_info->Relationship == RelationCache) {
						BYTE l_level = l_info->Cache.Level;
						if (l_level >= 1 && l_level <= 3) l_out [2 + l_level] += (EIF_INTEGER_64) l_info->Cache.CacheSize;
					}
					l_cursor += l_info->Size;
				}
				HeapFree (GetProcessHeap (), 0, l_raw);
				return EIF_TRUE;
			]"
		end

	c_virtualization: BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_BOOLEAN) (IsProcessorFeaturePresent (21) != 0);"
		end

	c_installed_memory: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"[
				ULONGLONG l_kb = 0;
				if (!GetPhysicallyInstalledSystemMemory (&l_kb)) return 0;
				return (EIF_INTEGER_64) l_kb * 1024;
			]"
		end

	c_display_device (a_index: INTEGER; a_buffer: POINTER; a_capacity: INTEGER): INTEGER
			-- Name of display device `a_index' into `a_buffer'; its length, 0 when it is not attached, -1 past the end.
		external
			"C inline use <windows.h>"
		alias
			"[
				DISPLAY_DEVICEW l_device;
				int l_length;
				ZeroMemory (&l_device, sizeof (l_device));
				l_device.cb = sizeof (l_device);
				if (!EnumDisplayDevicesW (NULL, (DWORD) $a_index, &l_device, 0)) return -1;
				if (!(l_device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP)) return 0;
				l_length = (int) wcslen (l_device.DeviceString);
				if (l_length > $a_capacity) l_length = $a_capacity;
				memcpy ((void *) $a_buffer, l_device.DeviceString, l_length * 2);
				return (EIF_INTEGER) l_length;
			]"
		end

	c_tick_count_64: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_INTEGER_64) GetTickCount64 ();"
		end

end
