note
	description: "[
		System readings from Windows: PDH counters (English paths), CPU
		topology, GlobalMemoryStatusEx, GetPerformanceInfo, and free space on
		fixed volumes. Support per metric is decided at creation by trying
		each source; on the reference machine that yields temperature not
		supported and package power available.

		A metric this machine does not supply is left out of the readings,
		which reads "not supported"; its reason is kept in `support_reason'.
		The self.* metrics are never read here: the frame builder measures the
		tool from its own process row.
	]"
	author: "Larry Rix"

class
	TM_WIN_SYSTEM_SOURCE

inherit
	TM_SYSTEM_SOURCE

create
	make

feature {NONE} -- Initialization

	make
			-- Open the counter query, read the topology, and decide support per metric.
		do
			create query.make
			create topology.make
			create support.make (metrics.count)
			create reasons.make (metrics.count)
			create package_instance.make_empty
			create last_readings.make
			last_readings.seal
			decide_support
		ensure
			every_metric_decided: across metrics.codes as ic all support.has (ic) end
			open: not is_closed
		end

feature -- Access

	support_of (a_code: INTEGER): INTEGER
			-- Decided at creation.
		do
			Result := support [a_code]
		end

	support_reason (a_code: INTEGER): STRING_32
			-- Decided at creation.
		do
			if attached reasons.item (a_code) as al_reason then
				Result := al_reason.twin
			else
				create Result.make_empty
			end
		end

	logical_processors: INTEGER
			-- From the topology.
		do
			Result := topology.logical_processor_count
		end

	topology: TM_CPU_TOPOLOGY
			-- Groups and efficiency classes.

feature -- Basic operations

	refresh
			-- Collect the counter query and read the gauges.
		local
			l_readings: TM_READINGS
		do
			create l_readings.make
			if query.counter_count > 0 then
				query.collect
			end
			put_total (l_readings, {TM_METRICS}.Cpu_busy_pct, busy_counter, 1.0, 0.0)
			put_total (l_readings, {TM_METRICS}.Cpu_utility_pct, utility_counter, 1.0, 0.0)
			put_total (l_readings, {TM_METRICS}.Mem_hard_faults_per_s, faults_counter, 1.0, 0.0)
			put_total (l_readings, {TM_METRICS}.Cpu_package_watts, power_counter, 0.001, 0.0)
				-- the energy meter reports milliwatts
			put_cores (l_readings)
			put_instances (l_readings, {TM_METRICS}.Disk_read_bps, disk_read_counter, 1.0, 0.0)
			put_instances (l_readings, {TM_METRICS}.Disk_write_bps, disk_write_counter, 1.0, 0.0)
			put_instances (l_readings, {TM_METRICS}.Disk_busy_pct, disk_idle_counter, -1.0, 100.0)
				-- busy = 100 - idle; "% Disk Time" exceeds 100 and is not used
			put_instances (l_readings, {TM_METRICS}.Temperature_c, thermal_counter, 0.1, -273.15)
				-- tenths of a kelvin
			put_memory (l_readings)
			put_volumes (l_readings)
			across metrics.codes as ic loop
				if not metrics.metric (ic).is_instanced and then not l_readings.has (ic, {STRING_32} "") then
					if support_of (ic) = {TM_READING_STATUS}.Available then
						l_readings.put (ic, {STRING_32} "", create {TM_READING}.make_unavailable)
					elseif support_of (ic) /= {TM_READING_STATUS}.Not_supported then
						l_readings.put (ic, {STRING_32} "", status_reading (support_of (ic)))
					end
				end
			end
			l_readings.seal
			last_readings := l_readings
		end

	close
			-- Close the counter query.
		do
			query.close
			is_closed := True
		ensure then
			query_closed: query.is_closed
		end

feature {NONE} -- Implementation

	query: TM_COUNTER_QUERY
			-- The one PDH query.

	support: HASH_TABLE [INTEGER, INTEGER]
			-- Support status by metric code.

	reasons: HASH_TABLE [STRING_32, INTEGER]
			-- Why a metric is not supplied, by code.

	busy_counter, core_counter, utility_counter, faults_counter: INTEGER
	disk_read_counter, disk_write_counter, disk_idle_counter: INTEGER
	power_counter, thermal_counter: INTEGER
			-- Counter indexes in `query'; 0 when the counter was refused.

	package_instance: STRING_32
			-- Energy meter instance ending in "_PKG", when there is one.

	decide_support
			-- Try each metric's source once.
		local
			l_clock: TM_SYSTEM_CLOCK
		do
			busy_counter := query.add_english ("\Processor Information(_Total)\%% Processor Time")
			core_counter := query.add_english ("\Processor Information(*)\%% Processor Time")
			utility_counter := query.add_english_uncapped ("\Processor Information(_Total)\%% Processor Utility")
			faults_counter := query.add_english ("\Memory\Page Reads/sec")
			disk_read_counter := query.add_english ("\PhysicalDisk(*)\Disk Read Bytes/sec")
			disk_write_counter := query.add_english ("\PhysicalDisk(*)\Disk Write Bytes/sec")
			disk_idle_counter := query.add_english ("\PhysicalDisk(*)\%% Idle Time")
			power_counter := query.add_english ("\Energy Meter(*)\Power")
			thermal_counter := query.add_english ("\Thermal Zone Information(*)\High Precision Temperature")
			if query.counter_count > 0 then
					-- Two collections, so rate counters have data before the first refresh.
				query.collect
				create l_clock.make
				l_clock.sleep_ms (100)
				query.collect
			end
			decide_counter ({TM_METRICS}.Cpu_busy_pct, busy_counter)
			decide_counter ({TM_METRICS}.Cpu_core_busy_pct, core_counter)
			decide_counter ({TM_METRICS}.Cpu_utility_pct, utility_counter)
			decide_counter ({TM_METRICS}.Mem_hard_faults_per_s, faults_counter)
			decide_counter ({TM_METRICS}.Disk_read_bps, disk_read_counter)
			decide_counter ({TM_METRICS}.Disk_write_bps, disk_write_counter)
			decide_counter ({TM_METRICS}.Disk_busy_pct, disk_idle_counter)
			decide_package_power
			decide_temperature
			across <<{TM_METRICS}.Mem_used_bytes, {TM_METRICS}.Mem_available_bytes, {TM_METRICS}.Mem_commit_bytes,
					{TM_METRICS}.Mem_commit_limit_bytes, {TM_METRICS}.Mem_commit_pct>> as ic loop
				support.force ({TM_READING_STATUS}.Available, ic)
			end
			if fixed_drive_count > 0 then
				support.force ({TM_READING_STATUS}.Available, {TM_METRICS}.Volume_free_bytes)
			else
				refuse ({TM_METRICS}.Volume_free_bytes, {STRING_32} "no fixed drive")
			end
			refuse ({TM_METRICS}.Gpu_busy_pct, {STRING_32} "GPU counters are not read in Phase 1")
			refuse ({TM_METRICS}.Gpu_dedicated_bytes, {STRING_32} "GPU counters are not read in Phase 1")
			if c_has_battery then
				refuse ({TM_METRICS}.Battery_pct, {STRING_32} "battery reading arrives in a later phase")
				refuse ({TM_METRICS}.Battery_drain_watts, {STRING_32} "battery reading arrives in a later phase")
			else
				refuse ({TM_METRICS}.Battery_pct, {STRING_32} "no battery")
				refuse ({TM_METRICS}.Battery_drain_watts, {STRING_32} "no battery")
			end
			refuse ({TM_METRICS}.Lag_max_ms, {STRING_32} "the lag probe arrives in Phase 3")
			across <<{TM_METRICS}.Self_cpu_pct, {TM_METRICS}.Self_private_bytes, {TM_METRICS}.Sample_cost_ms>> as ic loop
				refuse (ic, {STRING_32} "measured per frame from this tool's own process row")
			end
		ensure
			every_metric_decided: across metrics.codes as ic all support.has (ic) end
		end

	decide_counter (a_code, a_counter: INTEGER)
			-- Supported when PDH accepted the counter.
		do
			if a_counter > 0 then
				support.force ({TM_READING_STATUS}.Available, a_code)
			else
				refuse (a_code, {STRING_32} "Windows refused the performance counter")
			end
		end

	decide_package_power
			-- Supported when an energy meter instance ends in "_PKG" (RAPL package).
		do
			if power_counter > 0 then
				across query.values (power_counter) as ic until not package_instance.is_empty loop
					if ic.instance.as_upper.ends_with ({STRING_32} "_PKG") then
						package_instance := ic.instance.twin
					end
				end
			end
			if package_instance.is_empty then
				refuse ({TM_METRICS}.Cpu_package_watts, {STRING_32} "no CPU package energy meter")
			else
				support.force ({TM_READING_STATUS}.Available, {TM_METRICS}.Cpu_package_watts)
			end
		end

	decide_temperature
			-- Supported when a thermal zone instance exists.
		do
			if thermal_counter > 0 and then not query.values (thermal_counter).is_empty then
				support.force ({TM_READING_STATUS}.Available, {TM_METRICS}.Temperature_c)
			else
				refuse ({TM_METRICS}.Temperature_c, {STRING_32} "no thermal zone instance")
			end
		end

	refuse (a_code: INTEGER; a_reason: STRING_32)
			-- Metric `a_code' is not supported, for `a_reason'.
		require
			reason_given: not a_reason.is_empty
		do
			support.force ({TM_READING_STATUS}.Not_supported, a_code)
			reasons.force (a_reason, a_code)
		end

feature {NONE} -- Reading counters

	put_total (a_readings: TM_READINGS; a_code, a_counter: INTEGER; a_scale, a_offset: REAL_64)
			-- The single value of system-wide metric `a_code': the "_Total" instance, the
			-- package instance for power, or the only instance.
		local
			l_value: detachable TM_COUNTER_VALUE
		do
			if support_of (a_code) = {TM_READING_STATUS}.Available and a_counter > 0 then
				across query.values (a_counter) as ic loop
					if a_code = {TM_METRICS}.Cpu_package_watts then
							-- Only the package meter: the energy meter's "_Total" instance reads 0.
						if ic.instance.same_string (package_instance) then
							l_value := ic
						end
					elseif ic.instance.is_empty or ic.instance.is_case_insensitive_equal ({STRING_32} "_Total") then
						l_value := ic
					end
				end
				if attached l_value as al_value then
					a_readings.put (a_code, {STRING_32} "", counter_reading (a_code, al_value, a_scale, a_offset))
				end
			end
		end

	put_instances (a_readings: TM_READINGS; a_code, a_counter: INTEGER; a_scale, a_offset: REAL_64)
			-- One reading per instance of per-device metric `a_code', "_Total" left out.
		do
			if support_of (a_code) = {TM_READING_STATUS}.Available and a_counter > 0 then
				across query.values (a_counter) as ic loop
					if not ic.instance.is_empty and then not ic.instance.same_string ({STRING_32} "_Total") then
						a_readings.put (a_code, ic.instance, counter_reading (a_code, ic, a_scale, a_offset))
					end
				end
			end
		end

	put_cores (a_readings: TM_READINGS)
			-- Per-core busy, instances "group,number" mapped to one flat index (R-4).
		local
			l_parts: LIST [STRING_32]
			l_group, l_number: INTEGER
		do
			if support_of ({TM_METRICS}.Cpu_core_busy_pct) = {TM_READING_STATUS}.Available and core_counter > 0 then
				across query.values (core_counter) as ic loop
					l_parts := ic.instance.split ({CHARACTER_32} ',')
					if l_parts.count = 2 and then l_parts [1].is_integer and then l_parts [2].is_integer then
						l_group := l_parts [1].to_integer
						l_number := l_parts [2].to_integer
						if l_group >= 0 and l_group < topology.group_count and then
								l_number >= 0 and l_number < topology.group_size (l_group) then
							a_readings.put ({TM_METRICS}.Cpu_core_busy_pct, topology.flat_index (l_group, l_number).out.to_string_32,
								counter_reading ({TM_METRICS}.Cpu_core_busy_pct, ic, 1.0, 0.0))
						end
					end
				end
			end
		end

	put_memory (a_readings: TM_READINGS)
			-- Physical memory and commit, from GlobalMemoryStatusEx and GetPerformanceInfo.
		local
			l_buffer: MANAGED_POINTER
			l_total, l_available, l_commit, l_limit: INTEGER_64
		do
			create l_buffer.make (32)
			if c_memory (l_buffer.item) then
				l_total := l_buffer.read_integer_64 (0)
				l_available := l_buffer.read_integer_64 (8)
				l_commit := l_buffer.read_integer_64 (16)
				l_limit := l_buffer.read_integer_64 (24)
				a_readings.put ({TM_METRICS}.Mem_used_bytes, {STRING_32} "", measured ({TM_METRICS}.Mem_used_bytes, (l_total - l_available).to_double))
				a_readings.put ({TM_METRICS}.Mem_available_bytes, {STRING_32} "", measured ({TM_METRICS}.Mem_available_bytes, l_available.to_double))
				a_readings.put ({TM_METRICS}.Mem_commit_bytes, {STRING_32} "", measured ({TM_METRICS}.Mem_commit_bytes, l_commit.to_double))
				a_readings.put ({TM_METRICS}.Mem_commit_limit_bytes, {STRING_32} "", measured ({TM_METRICS}.Mem_commit_limit_bytes, l_limit.to_double))
				if l_limit > 0 then
					a_readings.put ({TM_METRICS}.Mem_commit_pct, {STRING_32} "",
						measured ({TM_METRICS}.Mem_commit_pct, l_commit.to_double * 100.0 / l_limit.to_double))
				end
			end
		end

	put_volumes (a_readings: TM_READINGS)
			-- Free bytes on each fixed drive, instance "C:".
		local
			l_drives, i: INTEGER
			l_buffer: MANAGED_POINTER
			l_name: STRING_32
		do
			if support_of ({TM_METRICS}.Volume_free_bytes) = {TM_READING_STATUS}.Available then
				l_drives := c_logical_drives
				create l_buffer.make (8)
				from
					i := 0
				until
					i = 26
				loop
					if l_drives.bit_test (i) and then c_drive_type (i) = Drive_fixed then
						create l_name.make (2)
						l_name.append_character (('A').plus (i).to_character_32)
						l_name.append_character (':')
						if c_free_bytes (i, l_buffer.item) then
							a_readings.put ({TM_METRICS}.Volume_free_bytes, l_name,
								measured ({TM_METRICS}.Volume_free_bytes, l_buffer.read_integer_64 (0).to_double))
						else
							a_readings.put ({TM_METRICS}.Volume_free_bytes, l_name, create {TM_READING}.make_unavailable)
						end
					end
					i := i + 1
				end
			end
		end

	counter_reading (a_code: INTEGER; a_value: TM_COUNTER_VALUE; a_scale, a_offset: REAL_64): TM_READING
			-- `a_value' scaled into metric `a_code'; invalid when PDH says the data is not valid.
		do
			if a_value.is_valid then
				Result := measured (a_code, a_value.value * a_scale + a_offset)
			else
				create Result.make_invalid
			end
		end

	measured (a_code: INTEGER; a_value: REAL_64): TM_READING
			-- `a_value' checked against metric `a_code'.
		do
			create Result.make_measured (a_value, metrics.metric (a_code))
		end

	fixed_drive_count: INTEGER
			-- Fixed drives present.
		local
			i, l_drives: INTEGER
		do
			l_drives := c_logical_drives
			from
				i := 0
			until
				i = 26
			loop
				if l_drives.bit_test (i) and then c_drive_type (i) = Drive_fixed then
					Result := Result + 1
				end
				i := i + 1
			end
		end

	Drive_fixed: INTEGER = 3
			-- DRIVE_FIXED.

feature {NONE} -- Externals

	c_memory (a_out: POINTER): BOOLEAN
			-- Total and available physical bytes, commit total and limit in bytes.
		external
			"C inline use <windows.h>, <psapi.h>"
		alias
			"[
				#if _WIN32_WINNT < 0x0602
				#error "simple_taskman needs _WIN32_WINNT >= 0x0602 (Windows 8 API): keep the external_cflag of simple_taskman.ecf"
				#endif
				MEMORYSTATUSEX l_status;
				PERFORMANCE_INFORMATION l_performance;
				EIF_INTEGER_64 *l_out = (EIF_INTEGER_64 *) $a_out;
				l_status.dwLength = sizeof (l_status);
				l_performance.cb = sizeof (l_performance);
				if (!GlobalMemoryStatusEx (&l_status)) return EIF_FALSE;
				if (!K32GetPerformanceInfo (&l_performance, sizeof (l_performance))) return EIF_FALSE;
				l_out [0] = (EIF_INTEGER_64) l_status.ullTotalPhys;
				l_out [1] = (EIF_INTEGER_64) l_status.ullAvailPhys;
				l_out [2] = (EIF_INTEGER_64) l_performance.CommitTotal * (EIF_INTEGER_64) l_performance.PageSize;
				l_out [3] = (EIF_INTEGER_64) l_performance.CommitLimit * (EIF_INTEGER_64) l_performance.PageSize;
				return EIF_TRUE;
			]"
		end

	c_logical_drives: INTEGER
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_INTEGER) GetLogicalDrives ();"
		end

	c_drive_type (a_letter: INTEGER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"[
				WCHAR l_root [4] = {0, L':', L'\\', 0};
				l_root [0] = (WCHAR) (L'A' + $a_letter);
				return (EIF_INTEGER) GetDriveTypeW (l_root);
			]"
		end

	c_free_bytes (a_letter: INTEGER; a_out: POINTER): BOOLEAN
			-- Blocking: a sleeping disk can stall GetDiskFreeSpaceExW.
		external
			"C blocking inline use <windows.h>"
		alias
			"[
				WCHAR l_root [4] = {0, L':', L'\\', 0};
				ULARGE_INTEGER l_free;
				l_root [0] = (WCHAR) (L'A' + $a_letter);
				if (!GetDiskFreeSpaceExW (l_root, &l_free, NULL, NULL)) return EIF_FALSE;
				*((EIF_INTEGER_64 *) $a_out) = (EIF_INTEGER_64) l_free.QuadPart;
				return EIF_TRUE;
			]"
		end

	c_has_battery: BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"[
				SYSTEM_POWER_STATUS l_power;
				if (!GetSystemPowerStatus (&l_power)) return EIF_FALSE;
				return (l_power.BatteryFlag != 128 && l_power.BatteryFlag != 255) ? EIF_TRUE : EIF_FALSE;
			]"
		end

invariant
	support_decided: support.count = metrics.count

end
