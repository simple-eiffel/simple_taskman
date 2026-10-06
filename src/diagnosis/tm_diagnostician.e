note
	description: "[
		Three rules over a window of frames (spec 04, Diagnosis; intent v2
		Phase 3, now Phase 4):

		  Memory pressure  (commit >= 90% or available < 5% of physical) and
		                   hard faults >= 200/s; culprit: largest private-bytes
		                   growth in the window, else largest private bytes.
		  Disk saturation  a disk's mean busy >= 80%; culprit: most bytes moved.
		  CPU saturation   mean CPU utility >= 85%; culprit: the process (by
		                   name) with the most CPU time in the window.

		Each needs coverage >= 0.8 and at least `Minimum_seconds' measured.
		Precedence memory, disk, CPU: memory pressure causes paging, which
		shows up as disk and CPU load, so the root cause ranks first; the
		others join as "also". No rule able to judge: inconclusive, naming
		what was missing. Rules able to judge but finding nothing: none.
	]"
	author: "Larry Rix"

class
	TM_DIAGNOSTICIAN

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make
		do
			create format
		end

feature -- Constants

	Commit_limit_pct: REAL_64 = 90.0
	Available_floor_pct: REAL_64 = 5.0
	Hard_faults_per_s: REAL_64 = 200.0
	Disk_busy_pct: REAL_64 = 80.0
	Cpu_busy_pct: REAL_64 = 85.0
	Minimum_coverage: REAL_64 = 0.8
	Minimum_seconds: REAL_64 = 10.0

feature -- Basic operations

	diagnose (a_window: TM_WINDOW): TM_VERDICT
			-- Why the machine was slow over `a_window', or that it was not, or that it cannot be told.
		local
			l_findings: ARRAYED_LIST [TM_VERDICT]
			l_judged: BOOLEAN
			l_missing: STRING_32
			l_memory, l_disk, l_cpu: detachable TM_VERDICT
		do
			create l_findings.make (3)
			create l_missing.make_empty
			if a_window.is_empty then
				create Result.make ({TM_VERDICT}.Inconclusive, {STRING_32} "Can't tell yet: no frames.")
			elseif (a_window.end_ticks - a_window.start_ticks).to_double < Minimum_seconds * {TM_CLOCK}.Ticks_per_second.to_double then
				create Result.make ({TM_VERDICT}.Inconclusive, {STRING_32} "Watching: the first verdict comes after "
					+ Minimum_seconds.truncated_to_integer.out.to_string_32 + {STRING_32} " seconds of frames.")
			else
				if judgeable (a_window, {TM_METRICS}.Mem_commit_pct, {STRING_32} "") and judgeable (a_window, {TM_METRICS}.Mem_hard_faults_per_s, {STRING_32} "") then
					l_judged := True
					l_memory := memory_rule (a_window)
				else
					add_missing (l_missing, {STRING_32} "memory")
				end
				if not a_window.last_frame.readings.instances ({TM_METRICS}.Disk_busy_pct).is_empty then
					l_judged := True
					l_disk := disk_rule (a_window)
				else
					add_missing (l_missing, {STRING_32} "disk")
				end
				if judgeable (a_window, {TM_METRICS}.Cpu_utility_pct, {STRING_32} "") then
					l_judged := True
					l_cpu := cpu_rule (a_window, {TM_METRICS}.Cpu_utility_pct)
				elseif judgeable (a_window, {TM_METRICS}.Cpu_busy_pct, {STRING_32} "") then
					l_judged := True
					l_cpu := cpu_rule (a_window, {TM_METRICS}.Cpu_busy_pct)
				else
					add_missing (l_missing, {STRING_32} "CPU")
				end
				if attached l_memory as al_memory then
					l_findings.extend (al_memory)
				end
				if attached l_disk as al_disk then
					l_findings.extend (al_disk)
				end
				if attached l_cpu as al_cpu then
					l_findings.extend (al_cpu)
				end
				if not l_findings.is_empty then
					Result := l_findings.first
					across l_findings as ic loop
						if ic /= Result then
							Result.add_also (ic.sentence)
						end
					end
				elseif l_judged then
					Result := calm (a_window)
				else
					create Result.make ({TM_VERDICT}.Inconclusive, {STRING_32} "Can't tell: " + l_missing
						+ {STRING_32} " readings cover too little of the last " + seconds_text (a_window) + {STRING_32} ".")
				end
			end
		ensure
			found_has_evidence: Result.is_found implies not Result.evidence.is_empty
		end

feature {NONE} -- Rules

	memory_rule (a_window: TM_WINDOW): detachable TM_VERDICT
		local
			l_commit, l_faults: REAL_64
			l_available_pct: REAL_64
			l_used, l_available: TM_AGGREGATE
		do
			l_commit := a_window.aggregate ({TM_METRICS}.Mem_commit_pct, {STRING_32} "").reading.value
			l_faults := a_window.aggregate ({TM_METRICS}.Mem_hard_faults_per_s, {STRING_32} "").reading.value
			l_available_pct := 100.0
			l_used := a_window.aggregate ({TM_METRICS}.Mem_used_bytes, {STRING_32} "")
			l_available := a_window.aggregate ({TM_METRICS}.Mem_available_bytes, {STRING_32} "")
			if l_used.reading.is_available and l_available.reading.is_available
					and then l_used.reading.value + l_available.reading.value > 0.0 then
				l_available_pct := l_available.reading.value * 100.0 / (l_used.reading.value + l_available.reading.value)
			end
			if (l_commit >= Commit_limit_pct or l_available_pct < Available_floor_pct) and l_faults >= Hard_faults_per_s then
				create Result.make ({TM_VERDICT}.Memory_pressure, {STRING_32} "x")
				fill_memory (Result, a_window, l_commit, l_faults, l_available_pct)
			end
		end

	fill_memory (a_verdict: TM_VERDICT; a_window: TM_WINDOW; a_commit, a_faults, a_available_pct: REAL_64)
		local
			l_growth_name, l_big_name: STRING_32
			l_growth, l_big: REAL_64
			l_first: HASH_TABLE [INTEGER_64, TM_PROCESS_ID]
			l_frame: TM_FRAME
			i: INTEGER
			l_text: STRING_32
		do
			create l_first.make (64)
			create l_growth_name.make_empty
			create l_big_name.make_empty
			from i := 1 until i > a_window.count loop
				l_frame := a_window.frame (i)
				across l_frame.activities as ic loop
					if ic.has_resource ({TM_RESOURCE}.Memory) then
						if not l_first.has (ic.id) then
							l_first.force (ic.private_bytes, ic.id)
						end
						if ic.private_bytes.to_double - l_first.item (ic.id).to_double > l_growth then
							l_growth := ic.private_bytes.to_double - l_first.item (ic.id).to_double
							l_growth_name := ic.name
						end
						if i = a_window.count and then ic.private_bytes.to_double > l_big then
							l_big := ic.private_bytes.to_double
							l_big_name := ic.name
						end
					end
				end
				i := i + 1
			end
			l_text := {STRING_32} "Slow because memory is full: commit " + format.percent (a_commit) + {STRING_32} " of the limit and "
				+ format.one_decimal (a_faults) + {STRING_32} " hard faults a second."
			if l_growth > 50_000_000.0 then
				a_verdict.set_culprit (l_growth_name)
				l_text.append ({STRING_32} " " + l_growth_name + {STRING_32} " grew " + format.bytes (l_growth.truncated_to_integer_64)
					+ {STRING_32} " in the last " + seconds_text (a_window) + {STRING_32} ".")
			elseif not l_big_name.is_empty then
				a_verdict.set_culprit (l_big_name)
				l_text.append ({STRING_32} " The largest is " + l_big_name + {STRING_32} " at " + format.bytes (l_big.truncated_to_integer_64) + {STRING_32} ".")
			end
			a_verdict.sentence.wipe_out
			a_verdict.sentence.append (l_text)
			a_verdict.add_evidence ({STRING_32} "commit " + format.percent (a_commit))
			a_verdict.add_evidence ({STRING_32} "hard faults " + format.one_decimal (a_faults) + {STRING_32} "/s")
			a_verdict.add_evidence ({STRING_32} "available " + format.percent (a_available_pct))
		end

	disk_rule (a_window: TM_WINDOW): detachable TM_VERDICT
		local
			l_disk: STRING_32
			l_busy, l_best: REAL_64
			l_aggregate: TM_AGGREGATE
			l_name: STRING_32
			l_moved: REAL_64
		do
			create l_disk.make_empty
			across a_window.last_frame.readings.instances ({TM_METRICS}.Disk_busy_pct) as ic loop
				l_aggregate := a_window.aggregate ({TM_METRICS}.Disk_busy_pct, ic)
				if l_aggregate.coverage >= Minimum_coverage and l_aggregate.measured_seconds >= Minimum_seconds
						and l_aggregate.reading.is_available then
					l_busy := l_aggregate.reading.value
					if l_busy >= Disk_busy_pct and l_busy > l_best then
						l_best := l_busy
						l_disk := ic
					end
				end
			end
			if not l_disk.is_empty then
				l_name := heaviest (a_window, {TM_RESOURCE}.Io_total)
				l_moved := total_of (a_window, l_name, {TM_RESOURCE}.Io_total)
				create Result.make ({TM_VERDICT}.Disk_saturation, {STRING_32} "Slow because disk " + l_disk + {STRING_32} " is saturated: "
					+ format.percent (l_best) + {STRING_32} " busy over the last " + seconds_text (a_window) + {STRING_32} ".")
				if not l_name.is_empty then
					Result.set_culprit (l_name)
					Result.sentence.append ({STRING_32} " " + l_name + {STRING_32} " moved " + format.bytes (l_moved.truncated_to_integer_64) + {STRING_32} ".")
				end
				Result.add_evidence ({STRING_32} "disk " + l_disk + {STRING_32} " busy " + format.percent (l_best))
			end
		end

	cpu_rule (a_window: TM_WINDOW; a_code: INTEGER): detachable TM_VERDICT
		local
			l_busy, l_share, l_total: REAL_64
			l_name: STRING_32
		do
			l_busy := a_window.aggregate (a_code, {STRING_32} "").reading.value
			if l_busy >= Cpu_busy_pct then
				l_name := heaviest (a_window, {TM_RESOURCE}.Cpu)
				create Result.make ({TM_VERDICT}.Cpu_saturation, {STRING_32} "Slow because the CPU is saturated: "
					+ format.percent (l_busy) + {STRING_32} " busy over the last " + seconds_text (a_window) + {STRING_32} ".")
				if not l_name.is_empty then
					l_total := all_cpu (a_window)
					if l_total > 0.0 then
						l_share := total_of (a_window, l_name, {TM_RESOURCE}.Cpu) * 100.0 / l_total
					end
					Result.set_culprit (l_name)
					Result.sentence.append ({STRING_32} " " + l_name + {STRING_32} " used " + format.percent (l_share) + {STRING_32} " of it.")
				end
				Result.add_evidence ({STRING_32} "CPU " + format.percent (l_busy))
			end
		end

	calm (a_window: TM_WINDOW): TM_VERDICT
			-- Nothing found, with the numbers that say so.
		local
			l_text: STRING_32
		do
			l_text := {STRING_32} "No bottleneck in the last " + seconds_text (a_window) + {STRING_32} ":"
			if judgeable (a_window, {TM_METRICS}.Cpu_utility_pct, {STRING_32} "") then
				l_text.append ({STRING_32} " CPU " + format.percent (a_window.aggregate ({TM_METRICS}.Cpu_utility_pct, {STRING_32} "").reading.value) + {STRING_32} ",")
			end
			if judgeable (a_window, {TM_METRICS}.Mem_commit_pct, {STRING_32} "") then
				l_text.append ({STRING_32} " memory commit " + format.percent (a_window.aggregate ({TM_METRICS}.Mem_commit_pct, {STRING_32} "").reading.value) + {STRING_32} ",")
			end
			l_text.append ({STRING_32} " busiest disk " + format.percent (busiest_disk (a_window)) + {STRING_32} ".")
			create Result.make ({TM_VERDICT}.None, l_text)
		end

feature {NONE} -- Helpers

	format: TM_FORMAT

	judgeable (a_window: TM_WINDOW; a_code: INTEGER; a_instance: STRING_32): BOOLEAN
			-- Is metric `a_code' measured over enough of `a_window'?
		local
			l_aggregate: TM_AGGREGATE
		do
			l_aggregate := a_window.aggregate (a_code, a_instance)
			Result := l_aggregate.reading.is_available and l_aggregate.coverage >= Minimum_coverage
				and l_aggregate.measured_seconds >= Minimum_seconds
		end

	heaviest (a_window: TM_WINDOW; a_resource: INTEGER): STRING_32
			-- Process name with the most of `a_resource' over the window (rate times seconds).
		local
			l_totals: HASH_TABLE [REAL_64, STRING_32]
			l_best: REAL_64
			i: INTEGER
			l_seconds: REAL_64
		do
			create Result.make_empty
			create l_totals.make (64)
			from i := 1 until i > a_window.count loop
				l_seconds := a_window.frame (i).duration.to_double / {TM_CLOCK}.Ticks_per_second.to_double
				across a_window.frame (i).activities as ic loop
					if ic.has_resource (a_resource) then
						l_totals.force (l_totals.item (ic.name) + ic.amount_of (a_resource) * l_seconds, ic.name)
					end
				end
				i := i + 1
			end
			across l_totals as ic loop
				if ic > l_best then
					l_best := ic
					Result := @ic.key
				end
			end
		end

	total_of (a_window: TM_WINDOW; a_name: STRING_32; a_resource: INTEGER): REAL_64
			-- `a_resource' used by processes called `a_name' over the window.
		local
			i: INTEGER
		do
			from i := 1 until i > a_window.count loop
				across a_window.frame (i).activities as ic loop
					if ic.has_resource (a_resource) and then ic.name.same_string (a_name) then
						Result := Result + ic.amount_of (a_resource) * a_window.frame (i).duration.to_double / {TM_CLOCK}.Ticks_per_second.to_double
					end
				end
				i := i + 1
			end
		end

	all_cpu (a_window: TM_WINDOW): REAL_64
			-- Core-seconds of every measured process over the window.
		local
			i: INTEGER
		do
			from i := 1 until i > a_window.count loop
				across a_window.frame (i).activities as ic loop
					if ic.has_resource ({TM_RESOURCE}.Cpu) then
						Result := Result + ic.cpu_cores * a_window.frame (i).duration.to_double / {TM_CLOCK}.Ticks_per_second.to_double
					end
				end
				i := i + 1
			end
		end

	busiest_disk (a_window: TM_WINDOW): REAL_64
		local
			l_aggregate: TM_AGGREGATE
		do
			across a_window.last_frame.readings.instances ({TM_METRICS}.Disk_busy_pct) as ic loop
				l_aggregate := a_window.aggregate ({TM_METRICS}.Disk_busy_pct, ic)
				if l_aggregate.reading.is_available then
					Result := Result.max (l_aggregate.reading.value)
				end
			end
		end

	seconds_text (a_window: TM_WINDOW): STRING_32
		local
			l_seconds: INTEGER_64
		do
			l_seconds := (a_window.end_ticks - a_window.start_ticks) // {TM_CLOCK}.Ticks_per_second
			if l_seconds >= 120 then
				Result := (l_seconds // 60).out.to_string_32 + {STRING_32} " minutes"
			else
				Result := l_seconds.out.to_string_32 + {STRING_32} " s"
			end
		end

	add_missing (a_list: STRING_32; a_name: STRING_32)
		do
			if not a_list.is_empty then
				a_list.append ({STRING_32} ", ")
			end
			a_list.append (a_name)
		end

end
