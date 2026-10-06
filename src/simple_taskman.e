note
	description: "[
		Headless entry point to simple_taskman: sample the machine, read the
		latest frame, see what this machine can measure; later, record, look
		back, and diagnose. No window, no console output, no background
		processor is created by this class.
	]"
	author: "Larry Rix"

class
	SIMPLE_TASKMAN

inherit
	TM_SHARED_METRICS

create
	make,
	make_with_sources

feature {NONE} -- Initialization

	make
			-- Live machine. Native process table when its self-check passes;
			-- documented fallback otherwise, with the reason kept.
		local
			l_native: TM_NATIVE_PROCESS_SOURCE
			l_system: TM_WIN_SYSTEM_SOURCE
			l_clock: TM_SYSTEM_CLOCK
			l_self: TM_SELF_PROCESS
		do
			create l_native.make
			if l_native.is_trusted then
				process_source := l_native
				process_source_kind := "native"
				native_self_check_passed := True
				create fallback_reason.make_empty
			else
				fallback_reason := l_native.last_self_check.failure.twin
				l_native.close
				process_source := create {TM_DOCUMENTED_PROCESS_SOURCE}.make
				process_source_kind := "documented"
			end
			create l_system.make
			create l_clock.make
			create l_self.make
			system_source := l_system
			clock := l_clock
			self_id := l_self.id
			create sampler.make (process_source, l_system, l_clock)
			sampler.set_self_id (l_self.id)
			create capabilities.make (l_system, process_source_kind, fallback_reason)
		ensure
			nothing_sampled: not has_frame
			source_known: process_source_kind.same_string ("native") or process_source_kind.same_string ("documented")
			native_only_when_trusted: process_source_kind.same_string ("native") implies native_self_check_passed
			fallback_says_why: process_source_kind.same_string ("documented") implies not fallback_reason.is_empty
			self_known: attached self_id as al_self and then al_self.pid > 0
			open: not is_closed
		end

	make_with_sources (a_processes: TM_PROCESS_SOURCE; a_system: TM_SYSTEM_SOURCE; a_clock: TM_CLOCK)
			-- Injected sources: tests, replay, demos.
		require
			trusted: a_processes.is_trusted
			open_sources: not a_processes.is_closed and not a_system.is_closed
		do
			process_source := a_processes
			process_source_kind := a_processes.kind_name.twin
			create fallback_reason.make_empty
			system_source := a_system
			clock := a_clock
			create sampler.make (a_processes, a_system, a_clock)
			create capabilities.make (a_system, process_source_kind, fallback_reason)
		ensure
			nothing_sampled: not has_frame
			sources_kept: process_source = a_processes and system_source = a_system and clock = a_clock
			kind_kept: process_source_kind.same_string (a_processes.kind_name)
			no_self: self_id = Void
				-- injected sources have no self row; a test that needs one calls set_self_id
			open: not is_closed
		end

feature -- Configuration

	set_nominal_interval (a_ms: INTEGER): like Current
			-- Expect a sample every `a_ms'; drives discontinuity detection.
		require
			sane: a_ms >= 250 and a_ms <= 60_000
		do
			sampler.set_nominal_interval (a_ms.to_integer_64 * Ticks_per_ms)
			Result := Current
		ensure
			kept: nominal_interval_ms = a_ms
			result_current: Result = Current
		end

	set_self_id (a_id: TM_PROCESS_ID): like Current
			-- Treat `a_id' as this tool, for its own readings (scripted runs).
		require
			not_idle: not a_id.is_idle_pseudo_process
		do
			self_id := a_id
			sampler.set_self_id (a_id)
			Result := Current
		ensure
			kept: self_id = a_id
			result_current: Result = Current
		end

	set_logger (a_logger: SIMPLE_LOGGER): like Current
			-- Send the library's own diagnostics to `a_logger'. A window or recorder
			-- target must create it with `make_to_file' (R-3): plain `make' prints.
		do
			logger := a_logger
			if fallback_reason.is_empty then
				a_logger.info ({STRING_32} "simple_taskman: process source " + process_source_kind.to_string_32)
			else
				a_logger.warn ({STRING_32} "simple_taskman: process source " + process_source_kind.to_string_32
					+ {STRING_32} "; native table refused: " + fallback_reason)
			end
			Result := Current
		ensure
			kept: logger = a_logger
			result_current: Result = Current
		end

feature -- Sampling

	sample
			-- Read the machine once.
		require
			open: not is_closed
		do
			sampler.sample
			if attached logger as al_logger then
				log_tick (al_logger)
			end
		ensure
			frame_after_first: old sampler.has_snapshot implies has_frame
		end

feature -- Access

	last_frame: TM_FRAME
			-- The most recent frame.
		require
			has_frame: has_frame
		do
			Result := sampler.last_frame
		end

	nominal_interval_ms: INTEGER
			-- Expected time between samples.
		do
			Result := (sampler.nominal_interval // Ticks_per_ms).to_integer_32
		end

	nominal_interval_ticks: INTEGER_64
			-- Same, in 100 ns ticks.
		do
			Result := sampler.nominal_interval
		end

	last_tick_cost: INTEGER_64
			-- Monotonic ticks the last `sample' took; what the self-budget governs (R-1).
		do
			Result := sampler.last_tick_cost
		end

	capabilities: TM_CAPABILITIES
			-- What this machine supplies and why not; includes the process source and its self-check.

	process_source_kind: STRING_8
			-- "native", "documented", or an injected source's kind.

	fallback_reason: STRING_32
			-- Why native was not used; empty when it was.

	self_id: detachable TM_PROCESS_ID
			-- This process; Void with injected sources (review issue 5).

feature -- Status report

	has_frame: BOOLEAN
			-- At least two samples taken?
		do
			Result := sampler.has_frame
		end

	native_self_check_passed: BOOLEAN
			-- Did the native table's layout check pass?

	is_closed: BOOLEAN
			-- Were the sources released?

feature -- Termination

	close
			-- Release the counter query (and, in Phase 2, the store). Explicit:
			-- simple_sql clients must not rely on dispose (survey, commit f233149).
		do
			process_source.close
			system_source.close
			is_closed := True
		ensure
			closed: is_closed
		end

feature {NONE} -- Implementation

	process_source: TM_PROCESS_SOURCE
	system_source: TM_SYSTEM_SOURCE
	clock: TM_CLOCK
	sampler: TM_SAMPLER
	logger: detachable SIMPLE_LOGGER

	Ticks_per_ms: INTEGER_64 = 10_000

	log_tick (a_logger: SIMPLE_LOGGER)
			-- Record the decisions of the last `sample': a failed read, a gap, a clock change.
			-- (Oracle rule: an unattended run logs its decisions, not just its errors.)
		do
			if not process_source.last_read_succeeded then
				a_logger.warn ({STRING_32} "simple_taskman: process read failed: " + process_source.last_error)
			end
			if has_frame then
				if last_frame.is_discontinuity then
					a_logger.warn ({STRING_32} "simple_taskman: discontinuity, "
						+ (last_frame.duration // {TM_CLOCK}.Ticks_per_second).out.to_string_32
						+ {STRING_32} " s without measurement")
				end
				if last_frame.is_clock_adjusted then
					a_logger.info ({STRING_32} "simple_taskman: wall clock changed; timeline offset now "
						+ (sampler.utc_offset // {TM_CLOCK}.Ticks_per_second).out.to_string_32 + {STRING_32} " s")
				end
			end
		end

invariant
	closed_sources_when_closed: is_closed implies (process_source.is_closed and system_source.is_closed)
	native_kind_is_trusted: process_source_kind.same_string ("native") implies native_self_check_passed

end
