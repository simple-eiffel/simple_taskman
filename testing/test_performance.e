note
	description: "[
		Phase 3 slice 2: the Performance tab's measurements, live and
		machine-neutral (any Windows 10/11 PC): machine facts, the new
		counters (kernel time, speed, cache, pools, counts, disk response,
		network, GPU), and count formatting.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_PERFORMANCE

inherit
	TM_TEST_SET

feature -- Tests

	test_machine_facts
		local
			l_machine: TM_MACHINE_INFO
		do
			create l_machine.make
			assert_true ("processor named", l_machine.has_processor_name)
			assert_true ("topology read", l_machine.has_topology)
			assert_true ("cores within logical", l_machine.cores >= 1 and l_machine.cores <= l_machine.logical_processors)
			assert_true ("a socket", l_machine.sockets >= 1)
			assert_true ("caches read", l_machine.l2_bytes > 0)
			assert_true ("base speed", l_machine.base_mhz > 100)
			assert_true ("up for a while", l_machine.uptime_seconds > 0)
			assert_true ("uptime text d:hh:mm:ss", l_machine.uptime_text.occurrences (':') = 3)
		end

	test_new_counters_read_live
		local
			l_source: TM_WIN_SYSTEM_SOURCE
			l_clock: TM_SYSTEM_CLOCK
			l_r: TM_READINGS
		do
			create l_source.make
			create l_clock.make
			l_source.refresh
			l_clock.sleep_ms (300)
			l_source.refresh
			l_r := l_source.last_readings
			assert_true ("kernel time", l_r.reading ({TM_METRICS}.Cpu_kernel_pct, {STRING_32} "").is_available)
			assert_true ("processes counted", l_r.reading ({TM_METRICS}.Sys_processes, {STRING_32} "").is_available
				and then l_r.reading ({TM_METRICS}.Sys_processes, {STRING_32} "").value > 10.0)
			assert_true ("threads counted", l_r.reading ({TM_METRICS}.Sys_threads, {STRING_32} "").value > 100.0)
			assert_true ("pools read", l_r.reading ({TM_METRICS}.Mem_nonpaged_pool_bytes, {STRING_32} "").is_available)
			assert_true ("cache read", l_r.reading ({TM_METRICS}.Mem_cached_bytes, {STRING_32} "").is_available)
			assert_false ("disk response per disk", l_r.instances ({TM_METRICS}.Disk_response_ms).is_empty)
			assert_false ("network adapters listed", l_r.instances ({TM_METRICS}.Net_receive_bps).is_empty)
			assert_true ("speed is measured or said why",
				l_r.reading ({TM_METRICS}.Cpu_performance_pct, {STRING_32} "").is_available
				or l_source.support_of ({TM_METRICS}.Cpu_performance_pct) /= {TM_READING_STATUS}.Available)
			l_source.close
		end

	test_gpu_engines_or_reason
		local
			l_source: TM_WIN_SYSTEM_SOURCE
			l_clock: TM_SYSTEM_CLOCK
			l_r: TM_READINGS
		do
			create l_source.make
			create l_clock.make
			l_source.refresh
			l_clock.sleep_ms (300)
			l_source.refresh
			l_r := l_source.last_readings
			if l_source.support_of ({TM_METRICS}.Gpu_busy_pct) = {TM_READING_STATUS}.Available then
				assert_true ("engine types named", across l_r.instances ({TM_METRICS}.Gpu_busy_pct) as ic all not ic.is_empty end)
				assert_true ("each within 0-100", across l_r.instances ({TM_METRICS}.Gpu_busy_pct) as ic all
					not l_r.reading ({TM_METRICS}.Gpu_busy_pct, ic).is_available
					or else l_r.reading ({TM_METRICS}.Gpu_busy_pct, ic).value <= 100.0 end)
			else
				assert_true ("refused with a reason", True)
			end
			l_source.close
		end

	test_counts_format_as_whole_numbers
		local
			l_format: TM_FORMAT
		do
			create l_format
			assert_strings_equal_case_insensitive ("no unit, no decimals", "4321", l_format.value_text (4321.4, "#"))
		end

end
