note
	description: "[
		Where recorded frames are kept and found again by time (spec 04,
		"Recorder Design"). Frames are appended in timeline order and come
		back as decoded frames (not complete: only significant processes).
		`frame_count', `earliest_ticks', and `latest_ticks' are kept up to
		date by every command, so the invariant reads only attributes.
	]"
	author: "Larry Rix"

deferred class
	TM_TRACE_STORE

feature -- Access

	policy: TM_RETENTION_POLICY
			-- Tier ages, size cap, and which processes are significant.

	appended: INTEGER
			-- Frames appended since this store was opened.

	frame_count: INTEGER
			-- Frames stored, in every tier.

	earliest_ticks: INTEGER_64
			-- Start of the oldest stored frame; 0 when empty.

	latest_ticks: INTEGER_64
			-- End of the newest stored frame; 0 when empty.

	last_error: STRING_32
			-- Why the last operation failed; empty after a success.

	window (a_from, a_to: INTEGER_64): TM_WINDOW
			-- Stored frames lying wholly inside [`a_from', `a_to'], oldest first.
		require
			open: is_open
			ordered: a_to > a_from
		deferred
		ensure
			inside: not Result.is_empty implies (Result.start_ticks >= a_from and Result.end_ticks <= a_to)
			no_more_than_stored: Result.count <= frame_count
		end

	frame_nearest (a_ticks: INTEGER_64): detachable TM_FRAME
			-- The stored frame whose span holds `a_ticks', else the nearest one; Void when empty or unreadable.
		require
			open: is_open
		deferred
		ensure
			none_when_empty: is_empty implies Result = Void
			said_why: (not is_empty and Result = Void) implies not last_error.is_empty
		end

	entries: ARRAYED_LIST [TM_TRACE_ENTRY]
			-- Every stored frame's bookkeeping, oldest first.
		require
			open: is_open
		deferred
		ensure
			counted: Result.count = frame_count
			ordered: across 2 |..| Result.count as ic all Result [ic].start_ticks >= Result [ic - 1].end_ticks end
		end

feature -- Status report

	is_open: BOOLEAN
			-- Can frames be read?

	is_writable: BOOLEAN
			-- Can frames be appended?

	is_empty: BOOLEAN
			-- No frames stored?
		do
			Result := frame_count = 0
		end

feature -- Element change

	append (a_frame: TM_FRAME)
			-- Store `a_frame' in tier 0.
		require
			writable: is_writable
			in_order: not is_empty implies a_frame.start_ticks >= latest_ticks
			not_before_epoch: a_frame.start_ticks >= 0
		deferred
		ensure
			counted: last_error.is_empty implies (appended = old appended + 1 and frame_count = old frame_count + 1)
			newest: last_error.is_empty implies latest_ticks = a_frame.end_ticks
			first_sets_start: (last_error.is_empty and old is_empty) implies earliest_ticks = a_frame.start_ticks
			start_kept: not old is_empty implies earliest_ticks = old earliest_ticks
			unchanged_on_failure: not last_error.is_empty implies (frame_count = old frame_count and latest_ticks = old latest_ticks)
		end

	flush
			-- Make appended frames durable and visible to readers.
		require
			writable: is_writable
		deferred
		end

	apply_retention
			-- One retention pass at the newest stored time: merge tiers 0 and 1 past their age, delete tier 2 past its age, honor the size cap.
		require
			writable: is_writable
		deferred
		ensure
			not_grown: frame_count <= old frame_count
			newest_kept: not old is_empty implies latest_ticks = old latest_ticks
		end

	pin (a_from, a_to: INTEGER_64)
			-- Keep every frame overlapping [`a_from', `a_to'] from merging and deletion.
		require
			writable: is_writable
			ordered: a_to > a_from
		deferred
		ensure
			same_count: frame_count = old frame_count
		end

	close
			-- Flush when writable and release the store.
		deferred
		ensure
			closed: not is_open and not is_writable
		end

invariant
	writable_is_open: is_writable implies is_open
	counts_non_negative: appended >= 0 and frame_count >= 0
	empty_has_no_span: frame_count = 0 implies (earliest_ticks = 0 and latest_ticks = 0)
	span_ordered: frame_count > 0 implies latest_ticks > earliest_ticks
	error_text_exists: last_error /= Void

end
