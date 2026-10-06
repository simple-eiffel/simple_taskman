note
	description: "[
		The sampling loop, on its own processor. It creates the facade, and so
		every native handle, on this processor, and talks to the window only
		through the slot, locking it for one short call at a time. Sampling,
		encoding, and sleeping all happen with no other processor locked
		(FR-056).

		When the window closes, the GUI requests a stop; the worker finishes
		its current tick, sees the request, closes its sources, and stops.
	]"
	author: "Larry Rix"

class
	TM_SAMPLING_WORKER

inherit
	EXCEPTION_MANAGER_FACTORY
		export
			{NONE} all
		end

create
	make

feature {NONE} -- Initialization

	make (a_interval_ms: INTEGER; a_store_path: separate READABLE_STRING_32)
			-- Worker sampling every `a_interval_ms'. `a_store_path' empty means no recording (Phase 1).
		require
			sane_interval: a_interval_ms >= 250 and a_interval_ms <= 60_000
		do
			interval_ms := a_interval_ms
			create store_path.make_from_separate (a_store_path)
			create codec.make
			create last_failure.make_empty
			create start_capabilities_text.make_empty
		ensure
			kept: interval_ms = a_interval_ms
			idle: not is_running
			no_slot: not attached slot
		end

feature -- Access

	interval_ms: INTEGER
			-- Starting interval; the self-budget may lengthen it.

	store_path: STRING_32
			-- Trace file to record into; empty for none.

	slot: detachable separate TM_FRAME_SLOT
			-- Where frames go.

feature -- Status report

	is_running: BOOLEAN
			-- Is `run' looping?

feature -- Element change

	attach_slot (a_slot: separate TM_FRAME_SLOT)
			-- Deliver frames to `a_slot'.
		require
			not_running: not is_running
		do
			slot := a_slot
		ensure
			attached_slot: slot = a_slot
		end

feature -- Execution

	run
			-- Sample until the slot asks to stop. Called asynchronously by the GUI;
			-- after launching, the GUI never calls this object again (a call would
			-- wait for the loop to end), only the slot. However it ends, the slot is
			-- told: a start-up or loop failure through its failure text, and every
			-- exit through `put_stopped' (review issue 4).
		require
			has_slot: attached slot
			not_running: not is_running
		local
			l_clock: TM_SYSTEM_CLOCK
			l_budget: TM_SELF_BUDGET
		do
			if attached slot as al_slot then
				is_running := True
				start
				if attached taskman_cell as al_taskman then
					create l_clock.make
					create l_budget.make (1.0, interval_ms, (interval_ms * 10).min (Maximum_interval_ms))
					deposit_capabilities (al_slot, start_capabilities_text)
					from
					until
						should_stop (al_slot) or failures >= Failure_limit
					loop
						tick (al_taskman, l_budget)
						if attached tick_text as al_text then
							deposit (al_slot, al_text)
						end
						l_clock.sleep_ms (pause_ms (l_budget.interval_ms, al_taskman))
					end
					if failures >= Failure_limit then
						report_failure (al_slot, last_failure)
					end
					safe_close (al_taskman)
				else
					report_failure (al_slot, last_failure)
				end
				report_stopped (al_slot)
				stop_reported := True
				is_running := False
			end
		ensure
			stopped: not is_running
			slot_told: stop_reported
		end

feature -- Status report (after run)

	stop_reported: BOOLEAN
			-- Did `run' tell the slot it stopped?

feature {NONE} -- Slot calls: each locks the slot for one short call

	deposit (a_slot: separate TM_FRAME_SLOT; a_text: STRING_8)
		require
			given: not a_text.is_empty
		do
			a_slot.put_frame (a_text)
		end

	deposit_capabilities (a_slot: separate TM_FRAME_SLOT; a_text: STRING_8)
		require
			given: not a_text.is_empty
		do
			a_slot.put_capabilities (a_text)
		end

	report_failure (a_slot: separate TM_FRAME_SLOT; a_text: STRING_32)
		do
			if a_text.is_empty then
				a_slot.put_failure ({STRING_32} "sampling failed")
			else
				a_slot.put_failure (a_text)
			end
		end

	report_stopped (a_slot: separate TM_FRAME_SLOT)
		do
			a_slot.put_stopped
		end

	should_stop (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.stop_requested
		end

feature {NONE} -- Implementation

	start
			-- Create the facade on this processor into `taskman_cell', with its capabilities
			-- encoded into `start_capabilities_text'; leave `taskman_cell' Void when start-up
			-- raised, with `last_failure' set. Takes no separate argument, so the slot is
			-- not locked during start-up.
		local
			l_retried: BOOLEAN
			l_taskman: SIMPLE_TASKMAN
		do
			taskman_cell := Void
			if not l_retried then
				create l_taskman.make
				l_taskman.set_nominal_interval (interval_ms).do_nothing
				start_capabilities_text := codec.encode_capabilities (l_taskman.capabilities)
				taskman_cell := l_taskman
			end
		ensure
			reason_when_failed: taskman_cell = Void implies not last_failure.is_empty
			capabilities_when_started: taskman_cell /= Void implies not start_capabilities_text.is_empty
		rescue
			last_failure := exception_text
			l_retried := True
			retry
		end

	safe_close (a_taskman: SIMPLE_TASKMAN)
			-- Close the facade; a failure while closing is kept, not raised.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_taskman.close
			end
		rescue
			last_failure := exception_text
			l_retried := True
			retry
		end

	start_capabilities_text: STRING_8
			-- Capability report encoded at start-up.

	taskman_cell: detachable SIMPLE_TASKMAN
			-- The facade made by `start'; Void when start-up failed.

	tick_text: detachable STRING_8
			-- Encoded frame of the last `tick'; Void before the first frame or after a failure.

	tick (a_taskman: SIMPLE_TASKMAN; a_budget: TM_SELF_BUDGET)
			-- Sample, assess own cost, and leave the encoded frame in `tick_text'.
			-- Takes no separate argument, so no other processor is locked while the
			-- machine is read. An exception counts a failure; `Failure_limit'
			-- consecutive failures stop the loop.
		local
			l_retried: BOOLEAN
		do
			tick_text := Void
			if not l_retried then
				a_taskman.sample
				if a_taskman.has_frame then
					a_budget.assess (a_taskman.last_tick_cost, a_taskman.nominal_interval_ticks)
					if a_budget.interval_ms /= a_taskman.nominal_interval_ms then
							-- keep discontinuity detection in step with a backed-off interval (A-110)
						a_taskman.set_nominal_interval (a_budget.interval_ms).do_nothing
					end
					tick_text := codec.encode (a_taskman.last_frame)
						-- Phase 2: the facade appends to its store inside `sample'
				end
				failures := 0
			end
		ensure
			text_only_with_a_frame: attached tick_text implies a_taskman.has_frame
		rescue
			failures := failures + 1
			last_failure := exception_text
			l_retried := True
			retry
		end

	pause_ms (a_interval_ms: INTEGER; a_taskman: SIMPLE_TASKMAN): INTEGER
			-- Interval minus this tick's cost, never below 50 ms.
		do
			Result := (a_interval_ms - (a_taskman.last_tick_cost // 10_000).to_integer_32).max (Minimum_pause_ms)
		ensure
			floor: Result >= Minimum_pause_ms
		end

	exception_text: STRING_32
			-- Description of the exception being rescued.
		do
			if attached exception_manager.last_exception as al_exception and then attached al_exception.description as al_text then
				create Result.make_from_string_general (al_text)
			else
				create Result.make_from_string ({STRING_32} "unknown exception")
			end
		ensure
			not_empty: not Result.is_empty
		end

	codec: TM_FRAME_CODEC
	failures: INTEGER
	last_failure: STRING_32

	Failure_limit: INTEGER = 3
	Minimum_pause_ms: INTEGER = 50
	Maximum_interval_ms: INTEGER = 60_000

invariant
	sane_interval: interval_ms >= 250 and interval_ms <= Maximum_interval_ms
	failures_non_negative: failures >= 0

end
