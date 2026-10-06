note
	description: "[
		Where the latest frame waits for the window. A mailbox on its own
		processor that never blocks: every routine is a field read or an
		assignment, so a call from the GUI returns at once and never queues
		behind sampling. Same shape as simple_chat's SUMMARY_SLOT.
	]"
	author: "Larry Rix"

class
	TM_FRAME_SLOT

create
	make

feature {NONE} -- Initialization

	make
			-- Empty slot.
		do
			create frame_text.make_empty
			create capabilities_text.make_empty
			create failure_text.make_empty
		ensure
			empty: not has_frame and not has_capabilities and not has_failure and not has_stopped
			counted_zero: deposited = 0 and dropped = 0
			running: not stop_requested
		end

feature -- Access

	frame_text: STRING_8
			-- The latest encoded frame.

	capabilities_text: STRING_8
			-- The encoded capability report.

	failure_text: STRING_32
			-- Why the worker stopped, when it failed.

	deposited: INTEGER
			-- Frames put so far.

	dropped: INTEGER
			-- Frames replaced before the window took them.

feature -- Status report

	has_frame: BOOLEAN
			-- Is a frame waiting?

	has_capabilities: BOOLEAN
			-- Has the report arrived?

	has_failure: BOOLEAN
			-- Did the worker stop on an error?

	requested_interval: INTEGER
			-- Interval the window asked for; 0 when it has not asked.

	stop_requested: BOOLEAN
			-- Has the window asked the worker to stop?

	has_stopped: BOOLEAN
			-- Has the worker left its loop, for any reason (review issue 4)?

feature -- Element change (worker side)

	put_frame (a_text: separate READABLE_STRING_8)
			-- The latest frame. Copied, so nothing of the worker's is held.
		require
			given: not a_text.is_empty
		do
			if has_frame then
				dropped := dropped + 1
			end
			create frame_text.make_from_separate (a_text)
			has_frame := True
			deposited := deposited + 1
		ensure
			ready: has_frame
			counted: deposited = old deposited + 1
			dropped_if_unread: old has_frame implies dropped = old dropped + 1
			kept_if_read: not old has_frame implies dropped = old dropped
			copied: frame_text.count = a_text.count
			stop_unchanged: stop_requested = old stop_requested
		end

	put_capabilities (a_text: separate READABLE_STRING_8)
			-- The capability report.
		require
			given: not a_text.is_empty
		do
			create capabilities_text.make_from_separate (a_text)
			has_capabilities := True
		ensure
			ready: has_capabilities
			copied: capabilities_text.count = a_text.count
		end

	put_failure (a_text: separate READABLE_STRING_32)
			-- The worker stopped on an error, and this is why.
		require
			given: not a_text.is_empty
		do
			create failure_text.make_from_separate (a_text)
			has_failure := True
		ensure
			failed: has_failure
			copied: failure_text.count = a_text.count
		end

	put_stopped
			-- The worker has left its loop and released its sources.
		do
			has_stopped := True
		ensure
			stopped: has_stopped
			frame_unchanged: has_frame = old has_frame and deposited = old deposited and dropped = old dropped
		end

feature -- Element change (GUI side)

	clear
			-- The frame was taken.
		do
			has_frame := False
		ensure
			taken: not has_frame
			counts_kept: deposited = old deposited and dropped = old dropped
		end

	request_interval (a_ms: INTEGER)
			-- Ask the worker to sample every `a_ms' from its next tick (Settings, update speed).
		require
			sane: a_ms >= 250 and a_ms <= 60_000
		do
			requested_interval := a_ms
		ensure
			kept: requested_interval = a_ms
		end

	request_stop
			-- Ask the worker to stop after its current tick.
		do
			stop_requested := True
		ensure
			requested: stop_requested
			frame_unchanged: has_frame = old has_frame and deposited = old deposited and dropped = old dropped
		end

invariant
	counts_non_negative: deposited >= 0 and dropped >= 0
	dropped_bounded: dropped <= deposited

end
