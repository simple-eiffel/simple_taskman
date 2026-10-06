note
	description: "[
		Test helper: a window stand-in on its own processor. It polls a frame
		slot, taking and decoding frames, until the slot reports the worker
		stopped or its rounds run out. Each slot access is one short call.
	]"
	author: "Larry Rix"

class
	TM_TEST_SLOT_READER

create
	make

feature {NONE} -- Initialization

	make (a_slot: separate TM_FRAME_SLOT)
			-- Reader of `a_slot'.
		do
			slot := a_slot
			create codec.make
		end

feature -- Access

	collected: INTEGER
			-- Frames taken from the slot.

	decoded: INTEGER
			-- Taken frames that decoded.

	is_finished: BOOLEAN
			-- Has `run' ended?

feature -- Execution

	run (a_rounds: INTEGER)
			-- Poll the slot every 5 ms, at most `a_rounds' times or until the worker stops.
		local
			l_clock: TM_SYSTEM_CLOCK
			i: INTEGER
		do
			create l_clock.make
			from
				i := 1
			until
				i > a_rounds or else worker_stopped (slot)
			loop
				if attached take (slot) as al_text then
					collected := collected + 1
					codec.decode (al_text)
					if codec.has_frame then
						decoded := decoded + 1
					end
				end
				l_clock.sleep_ms (5)
				i := i + 1
			end
			is_finished := True
		ensure
			finished: is_finished
		end

feature {NONE} -- Slot calls

	take (a_slot: separate TM_FRAME_SLOT): detachable STRING_8
		do
			if a_slot.has_frame then
				create Result.make_from_separate (a_slot.frame_text)
				a_slot.clear
			end
		end

	worker_stopped (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.has_stopped
		end

feature {NONE} -- Implementation

	slot: separate TM_FRAME_SLOT
	codec: TM_FRAME_CODEC

end
