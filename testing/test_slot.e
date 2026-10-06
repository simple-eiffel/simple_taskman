note
	description: "[
		Tests for TM_FRAME_SLOT, sequentially and as a SCOOP consumer would use
		it: the slot on its own processor, reached only through separate
		arguments, text copied on arrival. This is the skill's SCOOP consumer
		gate as well as a behaviour test.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_SLOT

inherit
	TM_TEST_SET

feature -- Tests: sequential

	test_put_then_clear
		note
			testing: "covers/{TM_FRAME_SLOT}.put_frame"
		local
			l_slot: TM_FRAME_SLOT
		do
			create l_slot.make
			l_slot.put_frame ("TMF1%T1")
			assert_true ("ready", l_slot.has_frame)
			assert_strings_equal_case_insensitive ("copied", "TMF1%T1", l_slot.frame_text)
			l_slot.clear
			assert_false ("taken", l_slot.has_frame)
			assert_integers_equal ("deposited", 1, l_slot.deposited)
		end

	test_unread_frame_counts_as_dropped
			-- At 1 s sampling and a 250 ms tick, a drop means the GUI stalled.
		note
			testing: "covers/{TM_FRAME_SLOT}.put_frame"
		local
			l_slot: TM_FRAME_SLOT
		do
			create l_slot.make
			l_slot.put_frame ("TMF1%T1")
			l_slot.put_frame ("TMF1%T2")
			assert_integers_equal ("dropped", 1, l_slot.dropped)
			assert_strings_equal_case_insensitive ("latest wins", "TMF1%T2", l_slot.frame_text)
		end

	test_stop_request_keeps_the_frame
		note
			testing: "covers/{TM_FRAME_SLOT}.request_stop"
		local
			l_slot: TM_FRAME_SLOT
		do
			create l_slot.make
			l_slot.put_frame ("TMF1%T1")
			l_slot.request_stop
			assert_true ("stop", l_slot.stop_requested)
			assert_true ("frame kept", l_slot.has_frame)
		end

	test_stopped_flag
			-- Review issue 4: the window can tell the worker has stopped.
		note
			testing: "covers/{TM_FRAME_SLOT}.put_stopped"
		local
			l_slot: TM_FRAME_SLOT
		do
			create l_slot.make
			assert_false ("running", l_slot.has_stopped)
			l_slot.put_frame ("TMF1%T1")
			l_slot.put_stopped
			assert_true ("stopped", l_slot.has_stopped)
			assert_true ("frame kept", l_slot.has_frame)
		end

	test_empty_frame_refused
		note
			testing: "covers/{TM_FRAME_SLOT}.put_frame"
		local
			l_slot: TM_FRAME_SLOT
		do
			create l_slot.make
			assert_true ("precondition fires", raises (agent l_slot.put_frame ("")))
		end

feature -- Tests: SCOOP consumer

	test_slot_on_its_own_processor
		note
			testing: "covers/{TM_FRAME_SLOT}.put_frame"
		local
			l_slot: separate TM_FRAME_SLOT
			l_text: detachable STRING_8
		do
			create l_slot.make
			deposit (l_slot, "TMF1%Tfrom the worker")
			l_text := collect (l_slot)
			assert_attached ("collected", l_text)
			if attached l_text as al_text then
				assert_strings_equal_case_insensitive ("copied across", "TMF1%Tfrom the worker", al_text)
			end
			assert_false ("taken", has_frame (l_slot))
		end

	test_worker_and_replayer_are_creatable_separately
			-- Creates both workers on their own processors and attaches the slot,
			-- without starting either loop.
		note
			testing: "covers/{TM_SAMPLING_WORKER}.attach_slot"
		local
			l_slot: separate TM_FRAME_SLOT
			l_worker: separate TM_SAMPLING_WORKER
			l_replayer: separate TM_FRAME_FILE_REPLAYER
		do
			create l_slot.make
			create l_worker.make (1000, {STRING_32} "")
			create l_replayer.make ({STRING_32} "C:\nowhere\frames.tmf", 1000)
			attach_worker (l_worker, l_slot)
			attach_replayer (l_replayer, l_slot)
			assert_true ("worker idle", worker_idle (l_worker))
		end

	test_replay_feeds_the_slot
		note
			testing: "covers/{TM_FRAME_FILE_REPLAYER}.run"
		local
			l_codec: TM_FRAME_CODEC
			l_path: STRING_32
			l_slot: separate TM_FRAME_SLOT
			l_replayer: separate TM_FRAME_FILE_REPLAYER
			l_tries: INTEGER
		do
			create l_codec.make
			l_path := scratch_path ({STRING_32} "taskman_replay_test.tmf")
			write_file (l_path, l_codec.encode (frame_with_cpu (Base_utc, 1, 10.0))
				+ l_codec.encode (frame_with_cpu (Base_utc + One_second, 1, 20.0))
				+ l_codec.encode (frame_with_cpu (Base_utc + 2 * One_second, 1, 30.0)))
			create l_slot.make
			create l_replayer.make (l_path, 50)
			attach_replayer (l_replayer, l_slot)
			launch_replayer (l_replayer)
			from
				l_tries := 0
			until
				l_tries >= 250 or else slot_stopped (l_slot)
			loop
				pause_ms (20)
				l_tries := l_tries + 1
			end
			assert_true ("stopped", slot_stopped (l_slot))
			assert_integers_equal ("three deposited", 3, slot_deposited (l_slot))
			assert_false ("no failure", slot_failed (l_slot))
			delete_file (l_path)
		end

	test_replay_of_a_missing_file_reports_failure
		note
			testing: "covers/{TM_FRAME_FILE_REPLAYER}.run"
		local
			l_slot: separate TM_FRAME_SLOT
			l_replayer: separate TM_FRAME_FILE_REPLAYER
			l_tries: INTEGER
		do
			create l_slot.make
			create l_replayer.make (scratch_path ({STRING_32} "taskman_no_such_file.tmf"), 50)
			attach_replayer (l_replayer, l_slot)
			launch_replayer (l_replayer)
			from
				l_tries := 0
			until
				l_tries >= 250 or else slot_stopped (l_slot)
			loop
				pause_ms (20)
				l_tries := l_tries + 1
			end
			assert_true ("stopped", slot_stopped (l_slot))
			assert_true ("failure reported", slot_failed (l_slot))
			assert_integers_equal ("nothing deposited", 0, slot_deposited (l_slot))
		end

feature {NONE} -- Separate calls

	launch_replayer (a_replayer: separate TM_FRAME_FILE_REPLAYER)
			-- Start the replay; asynchronous, returns at once.
		do
			a_replayer.run
		end

	pause_ms (a_ms: INTEGER)
			-- Sleep without holding any separate object. Polling must happen in the
			-- caller, one short slot call per check: a routine with the slot as an
			-- argument would hold its lock for the whole wait and starve the worker.
		do
			(create {TM_SYSTEM_CLOCK}.make).sleep_ms (a_ms)
		end

	slot_stopped (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.has_stopped
		end

	slot_failed (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.has_failure
		end

	slot_deposited (a_slot: separate TM_FRAME_SLOT): INTEGER
		do
			Result := a_slot.deposited
		end


	deposit (a_slot: separate TM_FRAME_SLOT; a_text: STRING_8)
		do
			a_slot.put_frame (a_text)
		end

	collect (a_slot: separate TM_FRAME_SLOT): detachable STRING_8
		do
			if a_slot.has_frame then
				create Result.make_from_separate (a_slot.frame_text)
				a_slot.clear
			end
		end

	has_frame (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.has_frame
		end

	attach_worker (a_worker: separate TM_SAMPLING_WORKER; a_slot: separate TM_FRAME_SLOT)
		do
			a_worker.attach_slot (a_slot)
		end

	attach_replayer (a_replayer: separate TM_FRAME_FILE_REPLAYER; a_slot: separate TM_FRAME_SLOT)
		do
			a_replayer.attach_slot (a_slot)
		end

	worker_idle (a_worker: separate TM_SAMPLING_WORKER): BOOLEAN
		do
			Result := not a_worker.is_running
		end

end
