note
	description: "[
		End-to-end test of the SCOOP handoff, as the window will use it: the
		sampling worker on its own processor reads this machine, encodes each
		frame, and deposits it in the slot on another processor; the test
		collects a frame, decodes it, asks the worker to stop, and sees it
		stop. Machine-neutral: it needs a Windows machine, not JACKJACK.

		Every slot access here is one short call from the test body; no
		routine holds the slot while waiting (oracle gotcha).
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_WORKER

inherit
	TM_TEST_SET

feature -- Tests

	test_worker_samples_hands_over_and_stops
		note
			testing: "covers/{TM_SAMPLING_WORKER}.run"
		local
			l_slot: separate TM_FRAME_SLOT
			l_worker: separate TM_SAMPLING_WORKER
			l_codec: TM_FRAME_CODEC
			l_frame_text, l_capabilities_text: detachable STRING_8
			l_tries: INTEGER
		do
			create l_slot.make
			create l_worker.make (250, {STRING_32} "")
			attach (l_worker, l_slot)
			launch (l_worker)
			from
				l_tries := 0
			until
				l_tries >= 400 or else deposited (l_slot) >= 3 or else has_failure (l_slot)
			loop
				pause_ms (20)
				l_tries := l_tries + 1
			end
			l_frame_text := collect (l_slot)
			l_capabilities_text := capabilities (l_slot)
			request_stop (l_slot)
			from
				l_tries := 0
			until
				l_tries >= 250 or else has_stopped (l_slot)
			loop
				pause_ms (20)
				l_tries := l_tries + 1
			end
			assert_false ("no failure", has_failure (l_slot))
			assert_true ("three frames deposited", deposited (l_slot) >= 3)
			assert_true ("worker stopped on request", has_stopped (l_slot))
			create l_codec.make
			if attached l_frame_text as al_text then
				l_codec.decode (al_text)
				assert_true ({STRING_32} "frame decodes: " + l_codec.last_error, l_codec.has_frame)
				assert_true ("processes in the frame", l_codec.last_frame.activity_count > 0)
				assert_true ("readings in the frame", l_codec.last_frame.readings.count > 0)
			else
				assert_true ("a frame was collected", False)
			end
			if attached l_capabilities_text as al_caps then
				l_codec.decode_capabilities (al_caps)
				assert_true ({STRING_32} "capabilities decode: " + l_codec.last_capabilities_error, l_codec.has_capabilities)
				assert_integers_equal ("every metric reported", metrics.count, l_codec.last_capabilities.count)
			else
				assert_true ("capabilities arrived", False)
			end
		end

feature {NONE} -- Separate calls: one short call each

	attach (a_worker: separate TM_SAMPLING_WORKER; a_slot: separate TM_FRAME_SLOT)
		do
			a_worker.attach_slot (a_slot)
		end

	launch (a_worker: separate TM_SAMPLING_WORKER)
			-- Asynchronous: returns at once.
		do
			a_worker.run
		end

	deposited (a_slot: separate TM_FRAME_SLOT): INTEGER
		do
			Result := a_slot.deposited
		end

	has_failure (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.has_failure
		end

	has_stopped (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.has_stopped
		end

	collect (a_slot: separate TM_FRAME_SLOT): detachable STRING_8
		do
			if a_slot.has_frame then
				create Result.make_from_separate (a_slot.frame_text)
				a_slot.clear
			end
		end

	capabilities (a_slot: separate TM_FRAME_SLOT): detachable STRING_8
		do
			if a_slot.has_capabilities then
				create Result.make_from_separate (a_slot.capabilities_text)
			end
		end

	request_stop (a_slot: separate TM_FRAME_SLOT)
		do
			a_slot.request_stop
		end

	pause_ms (a_ms: INTEGER)
			-- Sleep holding no separate object.
		do
			(create {TM_SYSTEM_CLOCK}.make).sleep_ms (a_ms)
		end

end
