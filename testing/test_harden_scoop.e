note
	description: "[
		Phase 6 concurrency and repetition: two reader processors race one
		live worker for the slot, with every deposit accounted for; a stop
		requested before the worker starts; workers started and stopped in
		quick succession; and the live sources read many times over.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_HARDEN_SCOOP

inherit
	TM_TEST_SET

feature -- Tests: SCOOP

	test_two_readers_race_one_worker
			-- Every deposited frame is taken by exactly one reader, dropped, or still waiting.
		note
			testing: "covers/{TM_FRAME_SLOT}.put_frame"
		local
			l_slot: separate TM_FRAME_SLOT
			l_worker: separate TM_SAMPLING_WORKER
			l_first, l_second: separate TM_TEST_SLOT_READER
			l_tries, l_collected, l_decoded: INTEGER
		do
			create l_slot.make
			create l_worker.make (250, {STRING_32} "")
			create l_first.make (l_slot)
			create l_second.make (l_slot)
			attach (l_worker, l_slot)
			launch (l_worker)
			launch_reader (l_first)
			launch_reader (l_second)
			from l_tries := 0 until l_tries >= 600 or else deposited (l_slot) >= 8 loop
				pause_ms (20)
				l_tries := l_tries + 1
			end
			request_stop (l_slot)
			from l_tries := 0 until l_tries >= 250 or else has_stopped (l_slot) loop
				pause_ms (20)
				l_tries := l_tries + 1
			end
				-- A query on a busy reader waits for its run to end: this joins both.
			l_collected := collected (l_first) + collected (l_second)
			l_decoded := decoded (l_first) + decoded (l_second)
			assert_true ("worker stopped", has_stopped (l_slot))
			assert_false ("no failure", has_failure (l_slot))
			assert_true ("eight deposited", deposited (l_slot) >= 8)
			assert_integers_equal ("every taken frame decoded", l_collected, l_decoded)
			assert_integers_equal ("taken + dropped + waiting = deposited", deposited (l_slot),
				l_collected + dropped (l_slot) + waiting (l_slot))
			bench ("two readers: deposited " + deposited (l_slot).out + ", taken " + l_collected.out
				+ ", dropped " + dropped (l_slot).out + ", waiting " + waiting (l_slot).out)
		end

	test_stop_requested_before_start
		note
			testing: "covers/{TM_SAMPLING_WORKER}.run"
		local
			l_slot: separate TM_FRAME_SLOT
			l_worker: separate TM_SAMPLING_WORKER
			l_tries: INTEGER
		do
			create l_slot.make
			request_stop (l_slot)
			create l_worker.make (250, {STRING_32} "")
			attach (l_worker, l_slot)
			launch (l_worker)
			from l_tries := 0 until l_tries >= 250 or else has_stopped (l_slot) loop
				pause_ms (20)
				l_tries := l_tries + 1
			end
			assert_true ("stopped", has_stopped (l_slot))
			assert_integers_equal ("no frames", 0, deposited (l_slot))
			assert_false ("no failure", has_failure (l_slot))
		end

	test_workers_started_and_stopped_in_succession
		note
			testing: "covers/{TM_SAMPLING_WORKER}.run"
		local
			l_slot: separate TM_FRAME_SLOT
			l_worker: separate TM_SAMPLING_WORKER
			i, l_tries, l_stopped: INTEGER
		do
			from i := 1 until i > 5 loop
				create l_slot.make
				create l_worker.make (250, {STRING_32} "")
				attach (l_worker, l_slot)
				launch (l_worker)
				pause_ms (50 * i)
				request_stop (l_slot)
				from l_tries := 0 until l_tries >= 250 or else has_stopped (l_slot) loop
					pause_ms (20)
					l_tries := l_tries + 1
				end
				if has_stopped (l_slot) and not has_failure (l_slot) then
					l_stopped := l_stopped + 1
				end
				i := i + 1
			end
			assert_integers_equal ("all five stopped cleanly", 5, l_stopped)
		end

feature -- Tests: live repetition

	test_native_table_read_two_hundred_times
		note
			testing: "covers/{TM_NATIVE_PROCESS_SOURCE}.read_all"
		local
			l_native: TM_NATIVE_PROCESS_SOURCE
			i, l_ok, l_fewest, l_most: INTEGER
			t0: INTEGER_64
		do
			create l_native.make
			if l_native.is_trusted then
				l_fewest := {INTEGER}.max_value
				t0 := now
				from i := 1 until i > 200 loop
					l_native.read_all
					if l_native.last_read_succeeded then
						l_ok := l_ok + 1
						l_fewest := l_fewest.min (l_native.last_samples.count)
						l_most := l_most.max (l_native.last_samples.count)
					end
					i := i + 1
				end
				bench ("native table: 200 reads in " + ms (now - t0) + ", " + l_fewest.out + " to " + l_most.out + " processes")
				assert_integers_equal ("all succeeded", 200, l_ok)
			else
				bench ("native table untrusted here: " + l_native.last_self_check.failure.out)
			end
		end

	test_documented_source_read_twenty_times
		note
			testing: "covers/{TM_DOCUMENTED_PROCESS_SOURCE}.read_all"
		local
			l_source: TM_DOCUMENTED_PROCESS_SOURCE
			i, l_ok: INTEGER
			t0: INTEGER_64
		do
			create l_source.make
			t0 := now
			from i := 1 until i > 20 loop
				l_source.read_all
				if l_source.last_read_succeeded then
					l_ok := l_ok + 1
				end
				i := i + 1
			end
			bench ("documented source: 20 reads in " + ms (now - t0))
			assert_integers_equal ("all succeeded", 20, l_ok)
		end

	test_system_source_refreshed_fifty_times
			-- Hammered with no pause, PDH now and then returns nothing for a rate
			-- counter (measured: 1-20 ms apart, the array call fails). The reading must
			-- then say "unavailable": never invalid, never missing ("not supported").
			-- At a realistic pace every refresh has a value.
		note
			testing: "covers/{TM_WIN_SYSTEM_SOURCE}.refresh"
		local
			l_system: TM_WIN_SYSTEM_SOURCE
			l_reading: TM_READING
			i, l_available, l_unavailable, l_paced: INTEGER
			t0: INTEGER_64
		do
			create l_system.make
			t0 := now
			from i := 1 until i > 50 loop
				l_system.refresh
				l_reading := l_system.last_readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "")
				if l_reading.is_available then
					l_available := l_available + 1
				elseif l_reading.is_unavailable then
					l_unavailable := l_unavailable + 1
				end
				i := i + 1
			end
			bench ("system source: 50 unpaced refreshes in " + ms (now - t0) + ": " + l_available.out
				+ " with a value, " + l_unavailable.out + " unavailable")
			assert_integers_equal ("only available or unavailable", 50, l_available + l_unavailable)
			from i := 1 until i > 10 loop
				pause_ms (250)
				l_system.refresh
				if l_system.last_readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "").is_available then
					l_paced := l_paced + 1
				end
				i := i + 1
			end
			assert_integers_equal ("a value every time at the worker's fastest pace (250 ms)", 10, l_paced)
			l_system.close
		end

feature {NONE} -- Separate calls: one short call each

	attach (a_worker: separate TM_SAMPLING_WORKER; a_slot: separate TM_FRAME_SLOT)
		do
			a_worker.attach_slot (a_slot)
		end

	launch (a_worker: separate TM_SAMPLING_WORKER)
		do
			a_worker.run
		end

	launch_reader (a_reader: separate TM_TEST_SLOT_READER)
		do
			a_reader.run (2_000)
		end

	collected (a_reader: separate TM_TEST_SLOT_READER): INTEGER
		do
			Result := a_reader.collected
		end

	decoded (a_reader: separate TM_TEST_SLOT_READER): INTEGER
		do
			Result := a_reader.decoded
		end

	deposited (a_slot: separate TM_FRAME_SLOT): INTEGER
		do
			Result := a_slot.deposited
		end

	dropped (a_slot: separate TM_FRAME_SLOT): INTEGER
		do
			Result := a_slot.dropped
		end

	waiting (a_slot: separate TM_FRAME_SLOT): INTEGER
		do
			if a_slot.has_frame then
				Result := 1
			end
		end

	has_stopped (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.has_stopped
		end

	has_failure (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.has_failure
		end

	request_stop (a_slot: separate TM_FRAME_SLOT)
		do
			a_slot.request_stop
		end

	pause_ms (a_ms: INTEGER)
		do
			(create {TM_SYSTEM_CLOCK}.make).sleep_ms (a_ms)
		end

	now: INTEGER_64
		do
			Result := (create {TM_SYSTEM_CLOCK}.make).monotonic_ticks
		end

	ms (a_ticks: INTEGER_64): STRING_8
		do
			Result := (a_ticks // 10_000).out + " ms"
		end

	bench (a_line: STRING_8)
		do
			io.put_string ("    bench: " + a_line + "%N")
			io.output.flush
		end

end
