note
	description: "[
		How long each resolution is kept, the size cap, and which processes are
		significant enough to record (spec 04 "Recorder Design"; D-008).
		Tier 0 holds 1 s frames, tier 1 holds 10 s merges, tier 2 holds 60 s
		merges. A frame leaves its tier once it is older than that tier's age
		limit: tier 0 and 1 frames are merged into the next tier, tier 2
		frames are deleted. Ages are measured on the recording's own timeline.
	]"
	author: "Larry Rix"

class
	TM_RETENTION_POLICY

create
	make_default,
	make

feature {NONE} -- Initialization

	make_default
			-- 1 hour, 24 hours, 30 days; 250 MB; 1% of a core, 100 KB/s, 256 MB; 40 processes a frame.
		do
			make (3_600, 86_400, 2_592_000, 250 * Mebibyte, 0.01, 102_400.0, 256 * Mebibyte, 40)
		ensure
			hour: age_limit_seconds (0) = 3_600
			day: age_limit_seconds (1) = 86_400
			month: age_limit_seconds (2) = 2_592_000
			capped: size_cap_bytes = 250 * Mebibyte
		end

	make (a_tier0_seconds, a_tier1_seconds, a_tier2_seconds, a_cap_bytes: INTEGER_64;
			a_cpu_cores, a_io_bps: REAL_64; a_private_bytes: INTEGER_64; a_max_processes: INTEGER)
			-- Policy with these age limits, size cap, significance thresholds, and process limit.
		require
			ages_positive: a_tier0_seconds > 0
			ages_grow: a_tier0_seconds <= a_tier1_seconds and a_tier1_seconds <= a_tier2_seconds
			cap_positive: a_cap_bytes > 0
			thresholds_non_negative: a_cpu_cores >= 0.0 and a_io_bps >= 0.0 and a_private_bytes >= 0
			room: a_max_processes > 0
		do
			ages := <<a_tier0_seconds, a_tier1_seconds, a_tier2_seconds>>
			ages.rebase (0)
			size_cap_bytes := a_cap_bytes
			cpu_cores_threshold := a_cpu_cores
			io_bps_threshold := a_io_bps
			private_bytes_threshold := a_private_bytes
			max_processes := a_max_processes
		ensure
			ages_kept: age_limit_seconds (0) = a_tier0_seconds and age_limit_seconds (1) = a_tier1_seconds
				and age_limit_seconds (2) = a_tier2_seconds
			cap_kept: size_cap_bytes = a_cap_bytes
			thresholds_kept: cpu_cores_threshold = a_cpu_cores and io_bps_threshold = a_io_bps
				and private_bytes_threshold = a_private_bytes
			room_kept: max_processes = a_max_processes
		end

feature -- Access

	age_limit_seconds (a_tier: INTEGER): INTEGER_64
			-- Age after which a frame leaves tier `a_tier'.
		require
			valid_tier: is_valid_tier (a_tier)
		do
			Result := ages [a_tier]
		ensure
			positive: Result > 0
		end

	age_limit_ticks (a_tier: INTEGER): INTEGER_64
			-- `age_limit_seconds' in timeline ticks.
		require
			valid_tier: is_valid_tier (a_tier)
		do
			Result := age_limit_seconds (a_tier) * {TM_CLOCK}.Ticks_per_second
		ensure
			scaled: Result = age_limit_seconds (a_tier) * {TM_CLOCK}.Ticks_per_second
		end

	resolution_seconds (a_tier: INTEGER): INTEGER_64
			-- Length of one frame in tier `a_tier': 1, 10, or 60 seconds.
		require
			valid_tier: is_valid_tier (a_tier)
		do
			inspect a_tier
			when 0 then
				Result := 1
			when 1 then
				Result := 10
			else
				Result := 60
			end
		ensure
			known: Result = 1 or Result = 10 or Result = 60
		end

	bucket_of (a_ticks: INTEGER_64; a_tier: INTEGER): INTEGER_64
			-- Which `a_tier'-resolution bucket the instant `a_ticks' falls in.
		require
			valid_tier: is_valid_tier (a_tier)
			not_before_epoch: a_ticks >= 0
		do
			Result := a_ticks // (resolution_seconds (a_tier) * {TM_CLOCK}.Ticks_per_second)
		ensure
			floor: Result = a_ticks // (resolution_seconds (a_tier) * {TM_CLOCK}.Ticks_per_second)
		end

	size_cap_bytes: INTEGER_64
			-- The recording file may not grow past this.

	cpu_cores_threshold: REAL_64
			-- A process using at least this many cores is significant.

	io_bps_threshold: REAL_64
			-- A process reading plus writing at least this many bytes a second is significant.

	private_bytes_threshold: INTEGER_64
			-- A process holding at least this much private memory is significant.

	max_processes: INTEGER
			-- At most this many processes are recorded in one frame.

	Tier_count: INTEGER = 3
			-- Tiers 0, 1, 2.

	Mebibyte: INTEGER_64 = 1_048_576

feature -- Status report

	is_valid_tier (a_tier: INTEGER): BOOLEAN
			-- Is `a_tier' one of the tiers?
		do
			Result := a_tier >= 0 and a_tier < Tier_count
		end

	is_significant (a_activity: TM_PROCESS_ACTIVITY; a_memory_pass: BOOLEAN): BOOLEAN
			-- Is `a_activity' worth recording: just born, busy in CPU or disk, or, in a memory pass,
			-- holding at least `private_bytes_threshold'? (Large quiet processes barely change from
			-- second to second; recording them once per tier 1 bucket keeps their history at the
			-- resolution tier 1 keeps anyway, at a tenth of the cost: measured 2026-10-06, 12.6 of 23
			-- recorded processes a frame were large and quiet.)
		do
			Result := a_activity.is_new
				or else (a_activity.has_resource ({TM_RESOURCE}.Cpu) and then a_activity.cpu_cores >= cpu_cores_threshold)
				or else (a_activity.has_resource ({TM_RESOURCE}.Io_total) and then a_activity.amount_of ({TM_RESOURCE}.Io_total) >= io_bps_threshold)
				or else (a_memory_pass and then a_activity.has_resource ({TM_RESOURCE}.Memory) and then a_activity.private_bytes >= private_bytes_threshold)
		ensure
			definition: Result = (a_activity.is_new
				or (a_activity.has_resource ({TM_RESOURCE}.Cpu) and then a_activity.cpu_cores >= cpu_cores_threshold)
				or (a_activity.has_resource ({TM_RESOURCE}.Io_total) and then a_activity.amount_of ({TM_RESOURCE}.Io_total) >= io_bps_threshold)
				or (a_memory_pass and then a_activity.has_resource ({TM_RESOURCE}.Memory) and then a_activity.private_bytes >= private_bytes_threshold))
		end

	is_memory_pass (a_frame: TM_FRAME): BOOLEAN
			-- Does `a_frame' reach a tier 1 bucket boundary (end inclusive), so large quiet processes are recorded in it?
			-- Consecutive frames reach each boundary exactly once; a frame of a coarser tier always does.
		require
			not_before_epoch: a_frame.start_ticks >= 0
		do
			Result := bucket_of (a_frame.start_ticks, 1) /= bucket_of (a_frame.end_ticks, 1)
		end

feature {NONE} -- Implementation

	ages: ARRAY [INTEGER_64]
			-- Age limits by tier, indexed 0..2.

invariant
	three_ages: ages.lower = 0 and ages.count = Tier_count
	ages_grow: ages [0] > 0 and ages [0] <= ages [1] and ages [1] <= ages [2]
	cap_positive: size_cap_bytes > 0
	thresholds_non_negative: cpu_cores_threshold >= 0.0 and io_bps_threshold >= 0.0 and private_bytes_threshold >= 0
	room: max_processes > 0

end
