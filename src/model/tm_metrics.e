note
	description: "[
		The one list of metrics and their codes (single choice). Codes are
		constants so they can be used in `inspect' and in contracts. Adding a
		metric appends a code; codes and names are never reused, because
		recordings refer to both (FR-NEW-010).

		Built once per processor through TM_SHARED_METRICS and never changed.
	]"
	author: "Larry Rix"

class
	TM_METRICS

create
	make

feature {NONE} -- Initialization

	make
			-- Build the catalog (spec 07, "TM_METRICS (registry) and its catalog").
		do
			create all_metrics_storage.make (Last_code)
			add (Cpu_busy_pct, "cpu.busy_pct", "%%", {STRING_32} "CPU busy", 0.0, 100.0, False, False)
			add (Cpu_core_busy_pct, "cpu.core.busy_pct", "%%", {STRING_32} "Core busy", 0.0, 100.0, True, False)
			add (Cpu_utility_pct, "cpu.utility_pct", "%%", {STRING_32} "CPU utility", 0.0, 400.0, False, False)
			add (Cpu_package_watts, "cpu.package_watts", "W", {STRING_32} "CPU package power", 0.0, 2000.0, False, False)
			add (Mem_used_bytes, "mem.used_bytes", "B", {STRING_32} "Memory used", 0.0, Two_to_50, False, False)
			add (Mem_available_bytes, "mem.available_bytes", "B", {STRING_32} "Memory available", 0.0, Two_to_50, False, False)
			add (Mem_commit_bytes, "mem.commit_bytes", "B", {STRING_32} "Committed", 0.0, Two_to_52, False, False)
			add (Mem_commit_limit_bytes, "mem.commit_limit_bytes", "B", {STRING_32} "Commit limit", 0.0, Two_to_52, False, False)
			add (Mem_commit_pct, "mem.commit_pct", "%%", {STRING_32} "Commit", 0.0, 100.0, False, False)
			add (Mem_hard_faults_per_s, "mem.hard_faults_per_s", "/s", {STRING_32} "Hard faults", 0.0, 10_000_000.0, False, False)
			add (Disk_read_bps, "disk.read_bps", "B/s", {STRING_32} "Disk read", 0.0, 100_000_000_000.0, True, False)
			add (Disk_write_bps, "disk.write_bps", "B/s", {STRING_32} "Disk write", 0.0, 100_000_000_000.0, True, False)
			add (Disk_busy_pct, "disk.busy_pct", "%%", {STRING_32} "Disk busy", 0.0, 100.0, True, False)
			add (Volume_free_bytes, "volume.free_bytes", "B", {STRING_32} "Volume free", 0.0, Two_to_60, True, False)
			add (Gpu_busy_pct, "gpu.busy_pct", "%%", {STRING_32} "GPU busy", 0.0, 100.0, True, False)
			add (Gpu_dedicated_bytes, "gpu.dedicated_bytes", "B", {STRING_32} "GPU dedicated memory", 0.0, Two_to_50, True, False)
			add (Temperature_c, "temperature.c", "C", {STRING_32} "Temperature", -50.0, 150.0, True, False)
			add (Battery_pct, "battery.pct", "%%", {STRING_32} "Battery", 0.0, 100.0, False, False)
			add (Battery_drain_watts, "battery.drain_watts", "W", {STRING_32} "Battery drain", -500.0, 500.0, False, False)
			add (Lag_max_ms, "lag.max_ms", "ms", {STRING_32} "Lag", 0.0, 600_000.0, False, True)
			add (Self_cpu_pct, "self.cpu_pct", "%%", {STRING_32} "taskman CPU", 0.0, 110_000.0, False, False)
			add (Self_private_bytes, "self.private_bytes", "B", {STRING_32} "taskman memory", 0.0, Two_to_50, False, False)
			add (Sample_cost_ms, "self.sample_cost_ms", "ms", {STRING_32} "Sample cost", 0.0, 60_000.0, False, True)
		ensure
			complete: count = Last_code
		end

feature -- Codes

	Cpu_busy_pct: INTEGER = 1
	Cpu_core_busy_pct: INTEGER = 2
	Cpu_utility_pct: INTEGER = 3
	Cpu_package_watts: INTEGER = 4
	Mem_used_bytes: INTEGER = 5
	Mem_available_bytes: INTEGER = 6
	Mem_commit_bytes: INTEGER = 7
	Mem_commit_limit_bytes: INTEGER = 8
	Mem_commit_pct: INTEGER = 9
	Mem_hard_faults_per_s: INTEGER = 10
	Disk_read_bps: INTEGER = 11
	Disk_write_bps: INTEGER = 12
	Disk_busy_pct: INTEGER = 13
	Volume_free_bytes: INTEGER = 14
	Gpu_busy_pct: INTEGER = 15
	Gpu_dedicated_bytes: INTEGER = 16
	Temperature_c: INTEGER = 17
	Battery_pct: INTEGER = 18
	Battery_drain_watts: INTEGER = 19
	Lag_max_ms: INTEGER = 20
	Self_cpu_pct: INTEGER = 21
	Self_private_bytes: INTEGER = 22
	Sample_cost_ms: INTEGER = 23

	Last_code: INTEGER = 23
			-- Highest code; codes run 1..Last_code with no holes.

feature -- Access

	metric (a_code: INTEGER): TM_METRIC
			-- The metric registered under `a_code'.
		require
			known: has_code (a_code)
		do
			Result := all_metrics_storage [a_code]
		ensure
			matches: Result.code = a_code
		end

	metric_named (a_name: READABLE_STRING_8): TM_METRIC
			-- The metric whose persistent name is `a_name'.
		require
			known: has_name (a_name)
		local
			l_found: detachable TM_METRIC
		do
			across all_metrics_storage as ic until attached l_found loop
				if ic.name.same_string (a_name) then
					l_found := ic
				end
			end
			check attached l_found as al_found then
					-- `has_name' guarantees a match.
				Result := al_found
			end
		ensure
			matches: Result.name.same_string (a_name)
		end

	all_metrics: ARRAYED_LIST [TM_METRIC]
			-- Every metric in code order; a fresh list each call.
		do
			create Result.make (count)
			across all_metrics_storage as ic loop
				Result.extend (ic)
			end
		ensure
			fresh: Result /= all_metrics_storage
			complete: Result.count = count
		end

	codes: ARRAYED_LIST [INTEGER]
			-- 1..Last_code; a fresh list each call.
		local
			i: INTEGER
		do
			create Result.make (count)
			from
				i := 1
			until
				i > count
			loop
				Result.extend (i)
				i := i + 1
			end
		ensure
			complete: Result.count = count
		end

	count: INTEGER
			-- Number of registered metrics.
		do
			Result := all_metrics_storage.count
		end

feature -- Status report

	has_code (a_code: INTEGER): BOOLEAN
			-- Is `a_code' registered?
		do
			Result := a_code >= 1 and a_code <= count
		end

	has_name (a_name: READABLE_STRING_8): BOOLEAN
			-- Is some metric named `a_name'?
		do
			Result := across all_metrics_storage as ic some ic.name.same_string (a_name) end
		end

feature {NONE} -- Implementation

	all_metrics_storage: ARRAYED_LIST [TM_METRIC]
			-- Metrics in code order: item `i' has code `i'.

	add (a_code: INTEGER; a_name, a_unit: STRING_8; a_label: STRING_32;
			a_minimum, a_maximum: REAL_64; a_is_instanced, a_is_peak: BOOLEAN)
			-- Register the next metric.
		require
			next_in_order: a_code = all_metrics_storage.count + 1
		do
			all_metrics_storage.extend (create {TM_METRIC}.make (a_code, a_name, a_unit, a_label,
				a_minimum, a_maximum, a_is_instanced, a_is_peak))
		ensure
			added: all_metrics_storage.count = old all_metrics_storage.count + 1
		end

	Two_to_50: REAL_64 = 1125899906842624.0
	Two_to_52: REAL_64 = 4503599627370496.0
	Two_to_60: REAL_64 = 1152921504606846976.0

invariant
	codes_dense: count = Last_code

end
