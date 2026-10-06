note
	description: "[
		The bound on the tool's own sampling cost and the policy for backing
		off (NFR-001: at most 1% of one logical processor). It governs
		sampling cost only: time spent in `sample' as a share of the nominal
		interval. Backing off then reduces exactly what was measured.
		Whole-process CPU, which includes rendering, is shown but not chased,
		because a longer interval cannot make rendering cheaper (intent Q3).
	]"
	author: "Larry Rix"

class
	TM_SELF_BUDGET

create
	make

feature {NONE} -- Initialization

	make (a_cpu_bound_pct: REAL_64; a_minimum_ms, a_maximum_ms: INTEGER)
			-- Budget of `a_cpu_bound_pct' percent of one processor, interval within [`a_minimum_ms', `a_maximum_ms'].
		require
			bound_positive: a_cpu_bound_pct > 0.0
			ordered: 0 < a_minimum_ms and a_minimum_ms <= a_maximum_ms
		do
			cpu_bound_pct := a_cpu_bound_pct
			minimum_ms := a_minimum_ms
			maximum_ms := a_maximum_ms
			interval_ms := a_minimum_ms
		ensure
			kept: cpu_bound_pct = a_cpu_bound_pct and minimum_ms = a_minimum_ms and maximum_ms = a_maximum_ms
			starts_fast: interval_ms = a_minimum_ms
			no_history: over_streak = 0 and under_streak = 0 and changes = 0
		end

feature -- Access

	cpu_bound_pct: REAL_64
			-- Allowed sampling cost, percent of one logical processor.

	minimum_ms, maximum_ms: INTEGER
			-- Interval bounds.

	interval_ms: INTEGER
			-- Recommended interval now.

	last_share_pct: REAL_64
			-- Sampling cost of the last assessed tick, percent of its interval.

	over_streak: INTEGER
			-- Consecutive ticks over the bound.

	under_streak: INTEGER
			-- Consecutive ticks at or under the bound.

	changes: INTEGER
			-- Times the interval has changed.

feature -- Basic operations

	assess (a_tick_cost, a_interval: INTEGER_64)
			-- Judge one tick: `a_tick_cost' monotonic ticks spent sampling out of
			-- an `a_interval' of nominal ticks (R-1, intent Q3).
		require
			cost_non_negative: a_tick_cost >= 0
			interval_positive: a_interval > 0
		do
			last_share_pct := a_tick_cost * 100.0 / a_interval
			if last_share_pct > cpu_bound_pct then
				under_streak := 0
				over_streak := over_streak + 1
				if over_streak >= Over_limit and interval_ms < maximum_ms then
					interval_ms := (interval_ms * 2).min (maximum_ms)
					changes := changes + 1
					over_streak := 0
				end
			else
				over_streak := 0
				under_streak := under_streak + 1
				if under_streak >= Under_limit and interval_ms > minimum_ms then
					interval_ms := (interval_ms // 2).max (minimum_ms)
					changes := changes + 1
					under_streak := 0
				end
			end
		ensure
			share_recorded: last_share_pct = a_tick_cost * 100.0 / a_interval
			within_bounds: interval_ms >= minimum_ms and interval_ms <= maximum_ms
			over_resets_under: last_share_pct > cpu_bound_pct implies under_streak = 0
			under_resets_over: last_share_pct <= cpu_bound_pct implies over_streak = 0
			backs_off: (last_share_pct > cpu_bound_pct and old over_streak + 1 >= Over_limit and old interval_ms < maximum_ms)
				implies interval_ms > old interval_ms
			never_speeds_up_while_over: last_share_pct > cpu_bound_pct implies interval_ms >= old interval_ms
			speeds_up_only_when_quiet: interval_ms < old interval_ms implies
				(last_share_pct <= cpu_bound_pct and old under_streak + 1 >= Under_limit)
			logged_on_change: interval_ms /= old interval_ms implies changes = old changes + 1
			quiet_when_unchanged: interval_ms = old interval_ms implies changes = old changes
			streaks_reset_on_change: interval_ms /= old interval_ms implies (over_streak = 0 and under_streak = 0)
		end

feature -- Constants

	Over_limit: INTEGER = 3
			-- Ticks over the bound before backing off.

	Under_limit: INTEGER = 30
			-- Ticks under the bound before speeding back up.

invariant
	bound_positive: cpu_bound_pct > 0.0
	ordered: 0 < minimum_ms and minimum_ms <= maximum_ms
	within_bounds: interval_ms >= minimum_ms and interval_ms <= maximum_ms
	streaks_non_negative: over_streak >= 0 and under_streak >= 0
	one_streak_at_a_time: over_streak = 0 or under_streak = 0
	changes_non_negative: changes >= 0

end
