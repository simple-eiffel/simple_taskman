# SPECIFICATION: simple_taskman

Date: 2026-10-03

> **Status of the code below.** These are specification skeletons. They have
> **not** been compiled. They fix names, signatures, and contracts for
> `/eiffel.intent` and `/eiffel.contracts`; the compiler gate runs when the
> classes are written for real. Bodies are given where they are short and
> settle a design question; elsewhere a body comment says what it does.

## Overview

simple_taskman is a diagnostic task manager for Windows in Eiffel: a headless
library that measures honestly, a recorder that remembers, a rule engine that
names the cause in words, and a simple_widgets window that shows all of it.
Phase 1 delivers the library core, the window, a thin CLI, and a stress tool.

## Shared conventions

- Time is `INTEGER_64` ticks of 100 ns. UTC ticks count from 1601-01-01 (Windows file time). Monotonic ticks count from an arbitrary origin.
- `Ticks_per_second: INTEGER_64 = 10_000_000`, defined once in `TM_CLOCK`.
- Status codes: `{TM_READING_STATUS}.Available` (0), `Unavailable` (1), `Not_supported` (2), `Access_denied` (3), `Invalid` (4). Zero is available, so the recorder's `CHECK` clauses read naturally.
- Classes that need the metric registry inherit `TM_SHARED_METRICS`, which exports `metrics: TM_METRICS` as a `once` function. Under SCOOP a `once` is per processor, so each processor builds its own read-only registry.

## Class Specifications

### TM_READING_STATUS (constants)

```eiffel
note
	description: "Codes for why a reading has, or has no, value."
	author: "Larry Rix"

class
	TM_READING_STATUS

feature -- Codes

	Available: INTEGER = 0
			-- Measured, finite, and inside the metric's valid range.

	Unavailable: INTEGER = 1
			-- The source exists but gave nothing this time.

	Not_supported: INTEGER = 2
			-- This machine has no such source.

	Access_denied: INTEGER = 3
			-- The source exists; our rights do not reach it.

	Invalid: INTEGER = 4
			-- The source answered with a value that cannot be true.

end
```

### TM_READING (immutable value)

```eiffel
note
	description: "[
		One observation of one metric: a measured value, or the stated reason
		there is none. A value can only enter through `make_measured', which
		checks it against its metric, so an impossible number cannot be stored.
	]"
	author: "Larry Rix"

class
	TM_READING

create
	make_measured,
	make_unavailable,
	make_not_supported,
	make_access_denied,
	make_invalid

feature {NONE} -- Initialization

	make_measured (a_value: REAL_64; a_metric: TM_METRIC)
			-- Available when `a_metric' accepts `a_value'; invalid otherwise.
		do
			if a_metric.accepts (a_value) then
				status := {TM_READING_STATUS}.Available
				stored_value := a_value
			else
				status := {TM_READING_STATUS}.Invalid
			end
		ensure
			available_when_accepted: a_metric.accepts (a_value) implies (is_available and value = a_value)
			invalid_otherwise: not a_metric.accepts (a_value) implies is_invalid
		end

	make_unavailable
		do
			status := {TM_READING_STATUS}.Unavailable
		ensure
			unavailable: is_unavailable
		end

	make_not_supported
		do
			status := {TM_READING_STATUS}.Not_supported
		ensure
			not_supported: is_not_supported
		end

	make_access_denied
		do
			status := {TM_READING_STATUS}.Access_denied
		ensure
			denied: is_access_denied
		end

	make_invalid
		do
			status := {TM_READING_STATUS}.Invalid
		ensure
			invalid: is_invalid
		end

feature -- Access

	status: INTEGER
			-- One of the {TM_READING_STATUS} codes.

	value: REAL_64
			-- The measured value.
		require
			available: is_available
		do
			Result := stored_value
		ensure
			definition: Result = stored_value
		end

	status_name: STRING_8
			-- "available", "unavailable", "not supported", "access denied", or "invalid".
		do
			inspect status
			when {TM_READING_STATUS}.Available then Result := "available"
			when {TM_READING_STATUS}.Unavailable then Result := "unavailable"
			when {TM_READING_STATUS}.Not_supported then Result := "not supported"
			when {TM_READING_STATUS}.Access_denied then Result := "access denied"
			else Result := "invalid"
			end
		ensure
			named: not Result.is_empty
		end

feature -- Status report

	is_available: BOOLEAN
		do Result := status = {TM_READING_STATUS}.Available end

	is_unavailable: BOOLEAN
		do Result := status = {TM_READING_STATUS}.Unavailable end

	is_not_supported: BOOLEAN
		do Result := status = {TM_READING_STATUS}.Not_supported end

	is_access_denied: BOOLEAN
		do Result := status = {TM_READING_STATUS}.Access_denied end

	is_invalid: BOOLEAN
		do Result := status = {TM_READING_STATUS}.Invalid end

feature {TM_READING} -- Implementation

	stored_value: REAL_64
			-- Zero unless available.

invariant
	status_known: status >= {TM_READING_STATUS}.Available and status <= {TM_READING_STATUS}.Invalid
	value_only_when_available: not is_available implies stored_value = 0.0
	available_is_finite: is_available implies
		not (stored_value.is_nan or stored_value.is_positive_infinity or stored_value.is_negative_infinity)

end
```

### TM_METRIC (immutable value)

```eiffel
note
	description: "What a metric is: stable name, unit, valid range, and how it aggregates."
	author: "Larry Rix"

class
	TM_METRIC

create
	make

feature {NONE} -- Initialization

	make (a_code: INTEGER; a_name, a_unit: STRING_8; a_label: STRING_32;
			a_minimum, a_maximum: REAL_64; a_is_instanced, a_is_peak: BOOLEAN)
		require
			code_positive: a_code > 0
			name_valid: is_valid_name (a_name)
			unit_given: not a_unit.is_empty
			label_given: not a_label.is_empty
			ordered_range: a_minimum <= a_maximum
		do
			code := a_code
			name := a_name.twin
			unit := a_unit.twin
			label := a_label.twin
			minimum := a_minimum
			maximum := a_maximum
			is_instanced := a_is_instanced
			is_peak := a_is_peak
		ensure
			kept: code = a_code and name.same_string (a_name) and minimum = a_minimum and maximum = a_maximum
			flags_kept: is_instanced = a_is_instanced and is_peak = a_is_peak
		end

feature -- Access

	code: INTEGER
	name: STRING_8
			-- Dotted lowercase, for example "cpu.package_watts". Persistent: part of the trace format.
	unit: STRING_8
	label: STRING_32
	minimum, maximum: REAL_64
	is_instanced: BOOLEAN
			-- Per core, per disk, per volume?
	is_peak: BOOLEAN
			-- Aggregate by maximum rather than duration-weighted mean?

feature -- Status report

	accepts (a_value: REAL_64): BOOLEAN
			-- Is `a_value' a value this metric can truly take?
		do
			Result := not (a_value.is_nan or a_value.is_positive_infinity or a_value.is_negative_infinity)
				and then a_value >= minimum and then a_value <= maximum
		end

	is_valid_name (a_name: READABLE_STRING_8): BOOLEAN
			-- Lowercase letters, digits, underscores, and single dots; no leading or trailing dot.
		do
			-- One pass over the characters.
		end

invariant
	code_positive: code > 0
	ordered_range: minimum <= maximum

end
```

### TM_METRICS (registry) and its catalog

`TM_METRICS` holds one `TM_METRIC` per code, built in `make`. Codes are
constants so they can be used in `inspect` and in contracts.

| Code | Constant | Name | Unit | Range | Instanced | Peak | P1 source |
|------|----------|------|------|-------|-----------|------|-----------|
| 1 | `Cpu_busy_pct` | `cpu.busy_pct` | % | 0..100 | | | PDH |
| 2 | `Cpu_core_busy_pct` | `cpu.core.busy_pct` | % | 0..100 | yes | | PDH |
| 3 | `Cpu_utility_pct` | `cpu.utility_pct` | % | 0..400 | | | PDH |
| 4 | `Cpu_package_watts` | `cpu.package_watts` | W | 0..2000 | | | PDH Energy Meter |
| 5 | `Mem_used_bytes` | `mem.used_bytes` | B | 0..2^50 | | | GlobalMemoryStatusEx |
| 6 | `Mem_available_bytes` | `mem.available_bytes` | B | 0..2^50 | | | GlobalMemoryStatusEx |
| 7 | `Mem_commit_bytes` | `mem.commit_bytes` | B | 0..2^52 | | | GetPerformanceInfo |
| 8 | `Mem_commit_limit_bytes` | `mem.commit_limit_bytes` | B | 0..2^52 | | | GetPerformanceInfo |
| 9 | `Mem_commit_pct` | `mem.commit_pct` | % | 0..100 | | | derived (7 / 8) |
| 10 | `Mem_hard_faults_per_s` | `mem.hard_faults_per_s` | /s | 0..10^7 | | | PDH |
| 11 | `Disk_read_bps` | `disk.read_bps` | B/s | 0..10^11 | yes | | PDH |
| 12 | `Disk_write_bps` | `disk.write_bps` | B/s | 0..10^11 | yes | | PDH |
| 13 | `Disk_busy_pct` | `disk.busy_pct` | % | 0..100 | yes | | PDH (100 - idle) |
| 14 | `Volume_free_bytes` | `volume.free_bytes` | B | 0..2^60 | yes | | GetDiskFreeSpaceExW |
| 15 | `Gpu_busy_pct` | `gpu.busy_pct` | % | 0..100 | yes | | PDH, slow query (stretch) |
| 16 | `Gpu_dedicated_bytes` | `gpu.dedicated_bytes` | B | 0..2^50 | yes | | PDH, slow query (stretch) |
| 17 | `Temperature_c` | `temperature.c` | °C | -50..150 | yes | | PDH thermal zone; not supported here |
| 18 | `Battery_pct` | `battery.pct` | % | 0..100 | | | later; not supported here |
| 19 | `Battery_drain_watts` | `battery.drain_watts` | W | -500..500 | | | later; not supported here |
| 20 | `Lag_max_ms` | `lag.max_ms` | ms | 0..600000 | | yes | P3 probe |
| 21 | `Self_cpu_pct` | `self.cpu_pct` | % of one processor | 0..100000 | | | own process row |
| 22 | `Self_private_bytes` | `self.private_bytes` | B | 0..2^50 | | | own process row |
| 23 | `Sample_cost_ms` | `self.sample_cost_ms` | ms | 0..60000 | | yes | sampler |

`Last_code: INTEGER = 23`. Invariant `codes_dense: count = Last_code`.
Adding a metric appends a code; codes and names are never reused, because
recordings refer to both (FR-NEW-010).

### TM_PROCESS_ID (immutable value)

```eiffel
note
	description: "[
		What makes a process the same process: its pid together with its
		creation time. A pid alone is a hotel room number.
	]"
	author: "Larry Rix"

class
	TM_PROCESS_ID

inherit
	HASHABLE
		redefine
			is_equal
		end

create
	make

feature {NONE} -- Initialization

	make (a_pid, a_creation_ticks: INTEGER_64)
		require
			pid_non_negative: a_pid >= 0
			creation_non_negative: a_creation_ticks >= 0
		do
			pid := a_pid
			creation_ticks := a_creation_ticks
		ensure
			kept: pid = a_pid and creation_ticks = a_creation_ticks
		end

feature -- Access

	pid: INTEGER_64
	creation_ticks: INTEGER_64

	hash_code: INTEGER
		do
			Result := (pid * 31 + creation_ticks).bit_and (0x7FFF_FFFF).to_integer_32
		end

feature -- Comparison

	is_equal (other: like Current): BOOLEAN
		do
			Result := pid = other.pid and creation_ticks = other.creation_ticks
		ensure then
			both_fields: Result = (pid = other.pid and creation_ticks = other.creation_ticks)
		end

feature -- Status report

	is_idle_pseudo_process: BOOLEAN
			-- The "System Idle Process" entry, whose CPU time is idle time.
		do
			Result := pid = 0
		end

invariant
	pid_non_negative: pid >= 0
	creation_non_negative: creation_ticks >= 0

end
```

### TM_READINGS (sealable collection)

```eiffel
class
	TM_READINGS

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make
		do
			create table.make (64)
			create instance_lists.make (16)
		ensure
			empty: count = 0
			open: not is_sealed
		end

feature -- Access

	reading (a_code: INTEGER; a_instance: READABLE_STRING_32): TM_READING
			-- The stored reading, or a not-supported one when nothing was stored.
		require
			known_metric: metrics.has_code (a_code)
		do
			if attached table.item (key (a_code, a_instance)) as al_reading then
				Result := al_reading
			else
				create Result.make_not_supported
			end
		ensure
			stored_if_present: has (a_code, a_instance) implies Result = readings_model [key (a_code, a_instance)]
			not_supported_if_absent: not has (a_code, a_instance) implies Result.is_not_supported
		end

	instances (a_code: INTEGER): ARRAYED_LIST [STRING_32]
			-- Instance names stored for `a_code', in insertion order; a fresh list.
		require
			known_metric: metrics.has_code (a_code)
			instanced: metrics.metric (a_code).is_instanced

	count: INTEGER
		do Result := table.count end

feature -- Status report

	has (a_code: INTEGER; a_instance: READABLE_STRING_32): BOOLEAN
		do Result := table.has (key (a_code, a_instance)) end

	is_sealed: BOOLEAN

feature -- Element change

	put (a_code: INTEGER; a_instance: READABLE_STRING_32; a_reading: TM_READING)
		require
			open: not is_sealed
			known_metric: metrics.has_code (a_code)
			instance_rule: metrics.metric (a_code).is_instanced = not a_instance.is_empty
		do
			-- table.force (a_reading, key (...)); record the instance in instance_lists on first sight.
		ensure
			stored: reading (a_code, a_instance) = a_reading
			others_unchanged: readings_model |=| (old readings_model).updated (key (a_code, a_instance), a_reading)
		end

	seal
		do
			is_sealed := True
		ensure
			sealed: is_sealed
			unchanged: readings_model |=| old readings_model
		end

feature -- Model

	readings_model: MML_MAP [STRING_8, TM_READING]
		do
			create Result
			across table as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = count
		end

	key (a_code: INTEGER; a_instance: READABLE_STRING_32): STRING_8
			-- "code|instance" with the instance in UTF-8. The only place this format is decided.
		local
			l_utf: UTF_CONVERTER
		do
			Result := a_code.out + "|" + l_utf.string_32_to_utf_8_string_8 (a_instance)
		end

feature {NONE} -- Implementation

	table: HASH_TABLE [TM_READING, STRING_8]
	instance_lists: HASH_TABLE [ARRAYED_LIST [STRING_32], INTEGER]

invariant
	count_matches_table: count = table.count

end
```

### TM_PROCESS_SAMPLE (value; three status groups)

```eiffel
class
	TM_PROCESS_SAMPLE

create
	make

feature {NONE} -- Initialization

	make (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32; a_parent_pid: INTEGER_64; a_session, a_threads: INTEGER)
		require
			parent_non_negative: a_parent_pid >= 0
			threads_non_negative: a_threads >= 0
		ensure
			identity_kept: id ~ a_id
			name_copied: name.same_string (a_name) and name /= a_name
			groups_unset: cpu_status = {TM_READING_STATUS}.Unavailable
				and memory_status = {TM_READING_STATUS}.Unavailable
				and io_status = {TM_READING_STATUS}.Unavailable

feature -- Access

	id: TM_PROCESS_ID
	name: STRING_32
	parent_pid: INTEGER_64
	session: INTEGER
	threads: INTEGER
	handles: INTEGER                       -- 0 when unknown; shown as "n/a" through memory_status

	cpu_status, memory_status, io_status: INTEGER

	user_ticks, kernel_ticks: INTEGER_64   -- require cpu_status = Available
	working_set, private_bytes: INTEGER_64 -- require memory_status = Available
	read_bytes, write_bytes: INTEGER_64    -- require io_status = Available

feature -- Element change (each callable once, while the group is still unset)

	set_cpu (a_user_ticks, a_kernel_ticks: INTEGER_64)
	deny_cpu (a_status: INTEGER)
	set_memory (a_working_set, a_private_bytes: INTEGER_64; a_handles: INTEGER)
	deny_memory (a_status: INTEGER)
	set_io (a_read_bytes, a_write_bytes: INTEGER_64)
	deny_io (a_status: INTEGER)
			-- Contracts as in 05-CONTRACT-DESIGN: each `set_' requires the group unset and
			-- non-negative values, ensures Available and leaves the other two groups unchanged.

invariant
	threads_non_negative: threads >= 0
	cpu_status_known: cpu_status >= {TM_READING_STATUS}.Available and cpu_status <= {TM_READING_STATUS}.Invalid
	memory_status_known: memory_status >= {TM_READING_STATUS}.Available and memory_status <= {TM_READING_STATUS}.Invalid
	io_status_known: io_status >= {TM_READING_STATUS}.Available and io_status <= {TM_READING_STATUS}.Invalid

end
```

### TM_PROCESS_ACTIVITY (value)

Creation procedures:

- `make_from_pair (a_before, a_after: TM_PROCESS_SAMPLE; a_seconds: REAL_64; a_logical_processors: INTEGER)`: survivor with rates.
- `make_born (a_after: TM_PROCESS_SAMPLE; a_logical_processors: INTEGER)`: newcomer; no rates this frame.
- `make_decoded (...)`: from the codec; every rate passes the same checks as a live one.

Rate rules inside `make_from_pair`:

```eiffel
	-- CPU
	if a_before.cpu_status = Available and a_after.cpu_status = Available then
		l_delta := (a_after.user_ticks + a_after.kernel_ticks) - (a_before.user_ticks + a_before.kernel_ticks)
		if l_delta < 0 then
			cpu_status := Invalid                                   -- a counter cannot run backward
		else
			l_cores := (l_delta / Ticks_per_second) / a_seconds
			if l_cores > a_logical_processors * Cpu_tolerance then
				cpu_status := Invalid                               -- DR-008: not clamped
			else
				cpu_status := Available
				cpu_cores := l_cores
				cpu_percent := l_cores * 100.0 / a_logical_processors
			end
		end
	else
		cpu_status := worse_of (a_before.cpu_status, a_after.cpu_status)   -- keep the more specific reason
	end
	-- IO: same shape over read_bytes and write_bytes; memory: copied from `a_after' (a gauge, not a rate)
```

`worse_of` prefers access denied over not supported over unavailable, so the
grid shows the most useful reason.

### TM_FRAME

Signatures and contracts are as in `05-CONTRACT-DESIGN.md` (creation
procedures `make`, `make_discontinuity`, `make_decoded`). Two additions:

```eiffel
	activities: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			-- All activities in arbitrary order; a fresh list each call (FR-057).
		do
			create Result.make (activity_count)
			across activity_table as ic loop Result.extend (ic) end
		ensure
			fresh_each_call: Result /= activities
			complete: Result.count = activity_count
		end

	self_activity (a_self: TM_PROCESS_ID): detachable TM_PROCESS_ACTIVITY
			-- This tool's own activity, when present.
		do
			Result := activity_table.item (a_self)
		end
```

### TM_FRAME_BUILDER and the self readings

```eiffel
	build (a_previous, a_current: TM_SNAPSHOT; a_logical_processors: INTEGER;
			a_self: TM_PROCESS_ID; a_previous_cost: INTEGER_64): TM_FRAME
```

Before sealing the frame's readings, `build` adds three readings about the
tool itself (I-008, FR-053):

- `self.cpu_pct`: the self activity's CPU cores times 100, a percent of one logical processor, matching NFR-001's wording. Unavailable when the tool is not in the table, as with scripted sources.
- `self.private_bytes`: from the self activity's memory group.
- `self.sample_cost_ms`: the *previous* tick's cost, because the current tick's cost is not known until the frame exists. The sampler passes it in.

The tool measures itself with the same table it shows the user, so its own
row in the grid and its overhead line in the status bar cannot disagree.

### TM_CLOCK and TM_SYSTEM_CLOCK

```eiffel
deferred class
	TM_CLOCK

feature -- Constants

	Ticks_per_second: INTEGER_64 = 10_000_000

feature -- Access

	utc_ticks: INTEGER_64
			-- Now, in 100 ns ticks since 1601-01-01 UTC.
		deferred
		ensure
			after_1601: Result > 0
		end

	monotonic_ticks: INTEGER_64
			-- A counter that never runs backward, in 100 ns ticks.
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Basic operations

	sleep_ms (a_ms: INTEGER)
		require
			non_negative: a_ms >= 0
		deferred
		end

end
```

```eiffel
class
	TM_SYSTEM_CLOCK

inherit
	TM_CLOCK

create
	make

feature {NONE} -- Initialization

	make
		do
			frequency := c_qpc_frequency
		ensure
			frequency_known: frequency > 0
		end

feature -- Access

	utc_ticks: INTEGER_64
		do
			Result := c_precise_utc_ticks
		end

	monotonic_ticks: INTEGER_64
			-- Split so that counter * 10^7 cannot overflow: a 10 MHz counter would
			-- overflow the naive product after about 10 days of uptime.
		local
			l_count: INTEGER_64
		do
			l_count := c_qpc_count
			Result := (l_count // frequency) * Ticks_per_second
				+ ((l_count \\ frequency) * Ticks_per_second) // frequency
		end

feature -- Basic operations

	sleep_ms (a_ms: INTEGER)
		do
			c_sleep (a_ms)
		end

feature {NONE} -- Implementation

	frequency: INTEGER_64

	c_precise_utc_ticks: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"[
				FILETIME ft;
				ULARGE_INTEGER u;
				GetSystemTimePreciseAsFileTime (&ft);
				u.LowPart = ft.dwLowDateTime;
				u.HighPart = ft.dwHighDateTime;
				return (EIF_INTEGER_64) u.QuadPart;
			]"
		end

	c_qpc_count: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"[
				LARGE_INTEGER c;
				QueryPerformanceCounter (&c);
				return (EIF_INTEGER_64) c.QuadPart;
			]"
		end

	c_qpc_frequency: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"[
				LARGE_INTEGER f;
				QueryPerformanceFrequency (&f);
				return (EIF_INTEGER_64) f.QuadPart;
			]"
		end

	c_sleep (a_ms: INTEGER)
			-- Blocking: the collector may run while this thread sleeps (C-015, A-103).
		external
			"C blocking inline use <windows.h>"
		alias
			"Sleep ((DWORD) $a_ms);"
		end

invariant
	frequency_known: frequency > 0

end
```

### TM_PROCESS_SOURCE (deferred) and TM_NATIVE_PROCESS_SOURCE

```eiffel
deferred class
	TM_PROCESS_SOURCE

feature -- Basic operations

	read_all
			-- Read every process now.
		require
			trusted: is_trusted
			open: not is_closed
		deferred
		ensure
			succeeded_or_said_why: last_read_succeeded xor not last_error.is_empty
		end

	close
		deferred
		ensure
			closed: is_closed
		end

feature -- Access

	last_samples: ARRAYED_LIST [TM_PROCESS_SAMPLE]
		require
			read: last_read_succeeded
		deferred
		ensure
			fresh: Result /= last_samples
		end

	last_error: STRING_32
	kind_name: STRING_8
		deferred
		end

feature -- Status report

	is_trusted: BOOLEAN
		deferred
		end

	last_read_succeeded: BOOLEAN
	is_closed: BOOLEAN

end
```

`TM_NATIVE_PROCESS_SOURCE` essentials:

```eiffel
feature {NONE} -- Initialization

	make
		do
			create buffer.make (Initial_buffer_bytes)        -- 1 MB; the spike needed 0.94 MB
			create last_error.make_empty
			create last_self_check.make_not_run
			query_function := c_locate_query_function
			if {PLATFORM}.is_64_bits and query_function /= default_pointer then
				run_self_check                               -- sets last_self_check
			else
				last_self_check.fail ("native table needs 64-bit Windows and ntdll!NtQuerySystemInformation")
			end
		ensure
			checked: last_self_check.has_run
			trusted_only_if_passed: is_trusted = last_self_check.passed
			reason_when_untrusted: not is_trusted implies not last_self_check.failure.is_empty
		end

feature -- Basic operations

	read_all
			-- One call returns every process. Grow the buffer and retry on
			-- STATUS_INFO_LENGTH_MISMATCH (0xC0000004), at most three times.
		do
			-- l_status := c_query (query_function, buffer.item, buffer.count, $l_returned)
			-- walk NextEntryOffset; for each entry build a TM_PROCESS_SAMPLE
			-- with all three groups set (the table gives them all)
		end

feature {NONE} -- Layout (x64; see 04-CLASS-DESIGN, "Native process table layout")

	Offset_next: INTEGER = 0x00
	Offset_threads: INTEGER = 0x04
	Offset_create_time: INTEGER = 0x20
	Offset_user_time: INTEGER = 0x28
	Offset_kernel_time: INTEGER = 0x30
	Offset_name_length: INTEGER = 0x38
	Offset_name_buffer: INTEGER = 0x40
	Offset_pid: INTEGER = 0x50
	Offset_parent_pid: INTEGER = 0x58
	Offset_handles: INTEGER = 0x60
	Offset_session: INTEGER = 0x64
	Offset_working_set: INTEGER = 0x90
	Offset_private_bytes: INTEGER = 0xB8
	Offset_read_transfer: INTEGER = 0xE8
	Offset_write_transfer: INTEGER = 0xF0

feature {NONE} -- Externals

	c_locate_query_function: POINTER
		external
			"C inline use <windows.h>"
		alias
			"[
				HMODULE h = GetModuleHandleW (L"ntdll.dll");
				return (h == NULL) ? NULL : (EIF_POINTER) GetProcAddress (h, "NtQuerySystemInformation");
			]"
		end

	c_query (a_function, a_buffer: POINTER; a_length: INTEGER; a_returned: TYPED_POINTER [INTEGER]): INTEGER
			-- NTSTATUS of SystemProcessInformation (class 5). Blocking (C-015).
		external
			"C blocking inline use <windows.h>"
		alias
			"[
				typedef LONG (WINAPI *tm_query_fn) (ULONG, PVOID, ULONG, PULONG);
				return (EIF_INTEGER) ((tm_query_fn) $a_function) (5, $a_buffer, (ULONG) $a_length, (PULONG) $a_returned);
			]"
		end

invariant
	buffer_present: buffer.count >= Minimum_buffer_bytes
	trusted_has_function: is_trusted implies query_function /= default_pointer
```

The image name is copied out of the buffer by its byte length with
`MANAGED_POINTER.make_from_pointer` and decoded as UTF-16 with surrogate
pairs, as simple_shell's clipboard code does (`shell_clipboard.e:15-50`).

**Self-check** (`run_self_check`), for the calling process:
1. Documented reads A: creation, user, and kernel times; working set and private usage; IO transfer counts; handle count.
2. Native `read_all`; find the own row by pid.
3. Documented reads B.
4. Pass when: creation time equal; each monotonic counter (CPU times, IO counts) satisfies `A <= native <= B`; working set and private bytes lie within `[min (A, B) - 4 MB, max (A, B) + 4 MB]`; handle count within `[min - 16, max + 16]`; session equal; image name equals the own module's file name.
5. Otherwise record which field failed and the three values.

### TM_FRAME_SLOT (handoff mailbox)

```eiffel
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
		do
			create frame_text.make_empty
			create capabilities_text.make_empty
			create failure_text.make_empty
		ensure
			empty: not has_frame and not has_capabilities and not has_failure
			counted_zero: deposited = 0 and dropped = 0
			running: not stop_requested
		end

feature -- Access

	frame_text: STRING_8
	capabilities_text: STRING_8
	failure_text: STRING_32
	deposited: INTEGER
	dropped: INTEGER

feature -- Status report

	has_frame: BOOLEAN
	has_capabilities: BOOLEAN
	has_failure: BOOLEAN
	stop_requested: BOOLEAN

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
		end

	put_capabilities (a_text: separate READABLE_STRING_8)
		require
			given: not a_text.is_empty
		do
			create capabilities_text.make_from_separate (a_text)
			has_capabilities := True
		ensure
			ready: has_capabilities
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

	request_stop
		do
			stop_requested := True
		ensure
			requested: stop_requested
		end

invariant
	counts_non_negative: deposited >= 0 and dropped >= 0
	dropped_bounded: dropped <= deposited

end
```

### TM_SAMPLING_WORKER (on its own processor)

```eiffel
note
	description: "[
		The sampling loop, on its own processor. It creates the facade, and so
		every native handle, on this processor, and talks to the window only
		through the slot, locking it for one short call at a time.
	]"
	author: "Larry Rix"

class
	TM_SAMPLING_WORKER

create
	make

feature {NONE} -- Initialization

	make (a_interval_ms: INTEGER; a_store_path: separate READABLE_STRING_32)
			-- `a_store_path' empty means no recording (Phase 1).
		require
			sane_interval: a_interval_ms >= 250 and a_interval_ms <= 60_000
		do
			interval_ms := a_interval_ms
			create store_path.make_from_separate (a_store_path)
			create codec
			create last_failure.make_empty
		ensure
			kept: interval_ms = a_interval_ms
			idle: not is_running
		end

feature -- Access

	interval_ms: INTEGER
	store_path: STRING_32
	slot: detachable separate TM_FRAME_SLOT

feature -- Status report

	is_running: BOOLEAN

feature -- Element change

	attach_slot (a_slot: separate TM_FRAME_SLOT)
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
			-- wait for the loop to end), only the slot.
		require
			has_slot: attached slot
			not_running: not is_running
		local
			l_taskman: SIMPLE_TASKMAN
			l_clock: TM_SYSTEM_CLOCK
			l_budget: TM_SELF_BUDGET
		do
			if attached slot as al_slot then
				is_running := True
				create l_clock.make
				create l_taskman.make
				l_taskman.set_nominal_interval (interval_ms).do_nothing
				create l_budget.make (1.0, interval_ms, interval_ms * 10)
				deposit_capabilities (al_slot, codec.encode_capabilities (l_taskman.capabilities))
				from
				until
					should_stop (al_slot) or failures >= Failure_limit
				loop
					if attached safe_tick (l_taskman, l_budget) as al_text then
						deposit (al_slot, al_text)          -- the only time the slot is locked: one copy
					end
					l_clock.sleep_ms (pause_ms (l_budget.interval_ms, l_taskman))
				end
				if failures >= Failure_limit then
					report_failure (al_slot, last_failure)
				end
				l_taskman.close
				is_running := False
			end
		ensure
			stopped: not is_running
		end

feature {NONE} -- Slot calls: each locks the slot for one short call

	deposit (a_slot: separate TM_FRAME_SLOT; a_text: STRING_8)
		do
			a_slot.put_frame (a_text)
		end

	deposit_capabilities (a_slot: separate TM_FRAME_SLOT; a_text: STRING_8)
		do
			a_slot.put_capabilities (a_text)
		end

	report_failure (a_slot: separate TM_FRAME_SLOT; a_text: STRING_32)
		do
			a_slot.put_failure (a_text)
		end

	should_stop (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.stop_requested
		end

feature {NONE} -- Implementation

	safe_tick (a_taskman: SIMPLE_TASKMAN; a_budget: TM_SELF_BUDGET): detachable STRING_8
			-- Sample, assess own cost, and return the encoded frame (Void before the
			-- first frame). Takes no separate argument, so no other processor is
			-- locked while the machine is read. An exception counts a failure;
			-- `Failure_limit' consecutive failures stop the loop.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_taskman.sample
				if a_taskman.has_frame then
					a_budget.assess (a_taskman.last_tick_cost, a_taskman.nominal_interval_ticks)
					if a_budget.interval_ms /= a_taskman.nominal_interval_ms then
							-- keep discontinuity detection in step with a backed-off interval (A-110)
						a_taskman.set_nominal_interval (a_budget.interval_ms).do_nothing
					end
					Result := codec.encode (a_taskman.last_frame)
						-- Phase 2: the facade appends to its store inside `sample'
				end
				failures := 0
			end
		rescue
			failures := failures + 1
			last_failure := description_of_last_exception     -- from EXCEPTION_MANAGER
			l_retried := True
			retry
		end

	pause_ms (a_interval_ms: INTEGER; a_taskman: SIMPLE_TASKMAN): INTEGER
			-- Interval minus this tick's cost, never below 50 ms.
		ensure
			floor: Result >= 50

	codec: TM_FRAME_CODEC
	failures: INTEGER
	last_failure: STRING_32
	Failure_limit: INTEGER = 3

end
```

The slot is locked only inside `deposit`, `deposit_capabilities`,
`report_failure`, and `should_stop`, each a routine whose only job is one call
on the slot. Sampling, encoding, sleeping, and (Phase 2) committing all happen
with no other processor locked. That is the property FR-056 needs.

When the window closes, the GUI requests a stop and its root procedure ends.
The SCOOP runtime lets the worker finish its current tick, see the request,
close its counter query, and stop.

### TM_APP (GUI root, excerpt)

```eiffel
	make
		local
			l_slot: separate TM_FRAME_SLOT
			l_worker: separate TM_SAMPLING_WORKER
		do
			create theme.make_dark
			create window.make ("simple_taskman", 80, 60, 1280, 820, theme)
			build_views                                 -- once; only contents change later (A-108)
			create codec
			create l_slot.make
			create l_worker.make (1000, {STRING_32} "")
			frame_slot := l_slot
			attach (l_worker, l_slot)
			launch (l_worker)                           -- asynchronous; returns at once
			window.set_on_tick (agent on_tick)          -- 250 ms heartbeat repaints anyway
			window.run                                  -- blocks until the window closes
			stop (l_slot)
		end

	on_tick
			-- Collect the latest frame, if any, and show it.
		do
			if attached frame_slot as al_slot then
				if not capabilities_shown and then attached collect_capabilities (al_slot) as al_caps then
					capability_view.show (codec.decode_capabilities (al_caps))
					capabilities_shown := True
				end
				if attached collect (al_slot) as al_text then
					codec.decode (al_text)
					if codec.has_frame then
						show_frame (codec.last_frame)       -- grid rows, heatmap cells, tiles, status bar
					else
						window.log_line ({STRING_32} "frame not decoded: " + codec.last_error)
					end
				end
			end
		end

	collect (a_slot: separate TM_FRAME_SLOT): detachable STRING_8
			-- One short call: copy the frame text, mark it taken.
		do
			if a_slot.has_frame then
				create Result.make_from_separate (a_slot.frame_text)
				a_slot.clear
			end
		end

	attach (a_worker: separate TM_SAMPLING_WORKER; a_slot: separate TM_FRAME_SLOT)
		do
			a_worker.attach_slot (a_slot)
		end

	launch (a_worker: separate TM_SAMPLING_WORKER)
		do
			a_worker.run
		end

	stop (a_slot: separate TM_FRAME_SLOT)
		do
			a_slot.request_stop
		end
```

The window never prints (`sw_window.e:9-12`); it logs through `log_line`.

### TM_FORMAT (library; the one formatting point)

```eiffel
	reading_text (a_reading: TM_READING; a_metric: TM_METRIC): STRING_32
			-- "61.2 W", "23%", "1.2 GB", or the status words. Never a number for a missing value.
		do
			if a_reading.is_available then
				Result := value_text (a_reading.value, a_metric.unit)
			else
				Result := a_reading.status_name.to_string_32
			end
		ensure
			words_when_missing: not a_reading.is_available implies Result.same_string_general (a_reading.status_name)
		end
```

The `words_when_missing` postcondition is DR-017 and NFR-009 as a contract.
Every view and the CLI go through this feature, and a test feeds it every
status.

### TM_FRAME_CODEC (text format v1)

One record per line, fields separated by a tab. Integers are decimal. Reals
are 16 hexadecimal digits of their IEEE 754 bits (exact). Text is UTF-8 with
`\t`, `\n`, and `\\` escaped.

```
TMF1  <start_ticks> <end_ticks> <duration> <logical_processors> <discontinuity 0|1> <complete 0|1> <omitted>
R     <metric_code> <instance> <status> <value_bits>
A     <pid> <creation> <name> <parent_pid> <session> <threads> <handles> <new 0|1>
      <cpu_status> <cores_bits> <memory_status> <working_set> <private_bytes>
      <io_status> <read_bps_bits> <write_bps_bits>
B     <pid> <creation>
X     <pid> <creation> <name>
```

Capabilities use the same scheme with a `TMC1` header and one `M` line per
metric: code, support status, reason text. The process source kind and
self-check result travel as `S` lines.

`decode` rejects unknown headers, wrong field counts, and unknown metric
codes, and reports which line failed. Every value goes back through
`TM_READING.make_measured` or the activity's own checks, so a damaged
recording can produce an *invalid* reading but never an impossible value.

### SIMPLE_TASKMAN (facade)

```eiffel
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
			system_source := l_system
			clock := l_clock
				-- Every remaining attribute is set before any unqualified call:
				-- void safety rejects a call on a Current whose attributes are
				-- not all attached yet.
			create sampler.make (process_source, l_system, l_clock)
			create self_id.make (c_current_pid, c_current_creation_ticks)
			create capabilities.make (l_system, process_source_kind, fallback_reason)
		ensure
			nothing_sampled: not has_frame
			source_known: process_source_kind.same_string ("native") or process_source_kind.same_string ("documented")
			native_only_when_trusted: process_source_kind.same_string ("native") implies native_self_check_passed
			fallback_says_why: process_source_kind.same_string ("documented") implies not fallback_reason.is_empty
			open: not is_closed
		end

	make_with_sources (a_processes: TM_PROCESS_SOURCE; a_system: TM_SYSTEM_SOURCE; a_clock: TM_CLOCK)
			-- Injected sources: tests, replay, demos.
		require
			trusted: a_processes.is_trusted
			open_sources: not a_processes.is_closed and not a_system.is_closed
		do
			process_source := a_processes
			process_source_kind := a_processes.kind_name
			create fallback_reason.make_empty
			system_source := a_system
			clock := a_clock
			create sampler.make (a_processes, a_system, a_clock)
			create self_id.make (0, 0)
				-- scripted sources have no self row; tests that need one script it
			create capabilities.make (a_system, process_source_kind, fallback_reason)
		ensure
			nothing_sampled: not has_frame
			sources_kept: process_source = a_processes and system_source = a_system and clock = a_clock
		end

feature -- Configuration

	set_nominal_interval (a_ms: INTEGER): like Current
		require
			sane: a_ms >= 250 and a_ms <= 60_000
		do
			sampler.set_nominal_interval (a_ms.to_integer_64 * 10_000)
			Result := Current
		ensure
			kept: sampler.nominal_interval = a_ms.to_integer_64 * 10_000
			result_current: Result = Current
		end

	set_logger (a_logger: SIMPLE_LOGGER): like Current
		do
			logger := a_logger
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
		ensure
			frame_after_first: old sampler.has_snapshot implies has_frame
		end

feature -- Access

	last_frame: TM_FRAME
		require
			has_frame: has_frame
		do
			Result := sampler.last_frame
		end

	nominal_interval_ms: INTEGER
			-- Expected time between samples.
		do
			Result := (sampler.nominal_interval // 10_000).to_integer_32
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
	fallback_reason: STRING_32
	self_id: TM_PROCESS_ID

feature -- Status report

	has_frame: BOOLEAN
		do
			Result := sampler.has_frame
		end

	native_self_check_passed: BOOLEAN
	is_closed: BOOLEAN

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

	c_current_pid: INTEGER_64
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_INTEGER_64) GetCurrentProcessId ();"
		end

	c_current_creation_ticks: INTEGER_64
			-- This process's creation time, from the documented call.
		external
			"C inline use <windows.h>"
		alias
			"[
				FILETIME c, e, k, u;
				ULARGE_INTEGER v;
				GetProcessTimes (GetCurrentProcess (), &c, &e, &k, &u);
				v.LowPart = c.dwLowDateTime;
				v.HighPart = c.dwHighDateTime;
				return (EIF_INTEGER_64) v.QuadPart;
			]"
		end

invariant
	closed_sources_when_closed: is_closed implies (process_source.is_closed and system_source.is_closed)
	native_kind_is_trusted: process_source_kind.same_string ("native") implies native_self_check_passed

end
```

### Phase 2 and 3 interfaces (signatures only)

```eiffel
deferred class TM_TRACE_STORE
feature
	append (a_frame: TM_FRAME)
		require writable: is_writable
		ensure counted: appended = old appended + 1
	flush
		require writable: is_writable
	window (a_from, a_to: INTEGER_64): TM_WINDOW
		require ordered: a_to > a_from
		ensure inside: not Result.is_empty implies (Result.start_ticks >= a_from and Result.end_ticks <= a_to)
	frame_nearest (a_ticks: INTEGER_64): detachable TM_FRAME
	earliest_ticks, latest_ticks: INTEGER_64
	is_writable: BOOLEAN
	appended: INTEGER
	close
end

class TM_SQLITE_TRACE_STORE  -- create make_writer (a_path; a_policy), make_reader (a_path)
class TM_MEMORY_TRACE_STORE  -- create make

class TM_VERDICT             -- create make_found, make_none, make_inconclusive (05-CONTRACT-DESIGN)
deferred class TM_RULE       -- kind, required_metrics, can_judge, judge (05-CONTRACT-DESIGN)
class TM_DIAGNOSTICIAN       -- create make (a_thresholds); diagnose (a_window): TM_VERDICT
```

## Dependencies

| Library | Purpose | Phase | Version |
|---------|---------|-------|---------|
| base (ISE) | Kernel | P1 | EiffelStudio 25.02 |
| testing (ISE) | EQA integration in the test target | P1 | 25.02 |
| simple_mml | Model queries in postconditions | P1 | current in D:\prod, 2026-10-03 |
| simple_logger | Optional library diagnostics | P1 | current |
| simple_testing | `TEST_SET_BASE` | P1 | current |
| simple_widgets, simple_shell, simple_cairo | GUI target | P1 | simple_widgets 0.8.1 |
| simple_datetime | Labels on the GUI and CLI | P1 | current |
| simple_cli | CLI and stress targets | P1 | current |
| simple_env | `LOCALAPPDATA` for the trace and log folders (R-3) | P1 | current |
| simple_sql (with eiffel_sqlite_2025) | Recorder | P2 | at or after commit f233149 (2026-09-28) |
| simple_json | Export | P2 | current |
| simple_toml | Machine contracts | P3 | current |
| simple_statistics | Baseline proposals | later | current; W-5 pending |

System import library: `pdh.lib` (Windows condition), new to the ecosystem.

## File Structure

```
D:\prod\simple_taskman\
├── simple_taskman.ecf
├── README.md, CHANGELOG.md, docs/          (Phase 5)
├── src/
│   ├── simple_taskman.e                    facade
│   ├── model/      tm_reading_status.e tm_reading.e tm_metric.e tm_metrics.e
│   │               tm_shared_metrics.e tm_readings.e tm_process_id.e
│   │               tm_process_sample.e tm_snapshot.e tm_resource.e
│   │               tm_process_activity.e tm_frame.e tm_series.e tm_aggregate.e
│   │               tm_window.e tm_process_total.e tm_clock.e tm_manual_clock.e
│   │               tm_format.e
│   ├── probe/      tm_system_clock.e tm_process_source.e
│   │               tm_native_process_source.e tm_documented_process_source.e
│   │               tm_self_check.e tm_system_source.e tm_win_system_source.e
│   │               tm_counter_query.e tm_counter_value.e tm_cpu_topology.e
│   │   └── scripted/  tm_scripted_process_source.e tm_scripted_system_source.e
│   ├── sampling/   tm_frame_builder.e tm_sampler.e tm_self_budget.e tm_capabilities.e
│   ├── handoff/    tm_frame_codec.e tm_frame_slot.e tm_sampling_worker.e
│   ├── recorder/   (P2)
│   ├── diagnosis/  (P3)
│   └── action/     (P4)
├── app/            tm_app.e tm_process_row.e tm_process_view.e tm_core_view.e
│                   tm_trend_view.e tm_capability_view.e
├── cli/            tm_cli.e tm_snapshot_command.e tm_capabilities_command.e
├── stress/         tm_stress.e tm_spinner.e tm_disk_load.e (inline C, write-through)
├── recorder_app/   tm_recorder_app.e                        (P2 SHOULD)
├── testing/        test_app.e lib_tests.e test_reading.e test_process_id.e
│                   test_readings.e test_frame_builder.e test_sampler.e
│                   test_window.e test_series.e test_codec.e test_self_budget.e
│                   test_format.e test_native_source.e test_system_source.e
│                   test_slot.e
├── YouTube/        (existing transcript)
└── .eiffel-workflow/
```

`TM_SELF_CHECK` (named in the tree above) holds a self-check's result: `has_run`, `passed`, `failure`, and the bracketing values. It is a small value class added here because both the native source and the capability report need it.

## ECF draft (UUID generated when the file is created; checked with `claude_tools uuid scan`)

```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<system xmlns="http://www.eiffel.com/developers/xml/configuration-1-23-0" name="simple_taskman" uuid="(generated)" library_target="simple_taskman">
	<target name="simple_taskman">
		<root all_classes="true"/>
		<file_rule><exclude>/EIFGENs$</exclude><exclude>/\..*$</exclude></file_rule>
		<option warning="warning">
			<assertions precondition="true" postcondition="true" check="true" invariant="true" loop="true" supplier_precondition="true"/>
		</option>
		<setting name="dead_code_removal" value="feature"/>
		<capability>
			<concurrency support="scoop" use="scoop"/>
			<void_safety support="all"/>
		</capability>
		<external_linker_flag value="pdh.lib"><condition><platform value="windows"/></condition></external_linker_flag>
		<library name="base" location="$ISE_LIBRARY\library\base\base.ecf"/>
		<library name="simple_mml" location="$SIMPLE_EIFFEL/simple_mml/simple_mml.ecf"/>
		<library name="simple_env" location="$SIMPLE_EIFFEL/simple_env/simple_env.ecf"/>
		<library name="simple_logger" location="$SIMPLE_EIFFEL/simple_logger/simple_logger.ecf"/>
		<cluster name="src" location=".\src\" recursive="true"/>
	</target>
	<target name="simple_taskman_tests" extends="simple_taskman">
		<root class="TEST_APP" feature="make"/>
		<setting name="console_application" value="true"/>
		<library name="testing" location="$ISE_LIBRARY\library\testing\testing.ecf"/>
		<library name="simple_testing" location="$SIMPLE_EIFFEL\simple_testing\simple_testing.ecf"/>
		<cluster name="testing" location=".\testing\" recursive="true"/>
	</target>
	<target name="taskman" extends="simple_taskman">
		<root class="TM_APP" feature="make"/>
		<setting name="console_application" value="false"/>
		<library name="simple_shell" location="$SIMPLE_EIFFEL/simple_shell/simple_shell.ecf"/>
		<library name="simple_cairo" location="$SIMPLE_EIFFEL/simple_cairo/simple_cairo.ecf"/>
		<library name="simple_widgets" location="$SIMPLE_EIFFEL/simple_widgets/simple_widgets.ecf"/>
		<library name="simple_datetime" location="$SIMPLE_EIFFEL/simple_datetime/simple_datetime.ecf"/>
		<cluster name="app" location=".\app\"/>
	</target>
	<target name="taskman_cli" extends="simple_taskman">
		<root class="TM_CLI" feature="make"/>
		<setting name="console_application" value="true"/>
		<library name="simple_cli" location="$SIMPLE_EIFFEL/simple_cli/simple_cli.ecf"/>
		<cluster name="cli" location=".\cli\"/>
	</target>
	<target name="taskman_stress" extends="simple_taskman">
		<root class="TM_STRESS" feature="make"/>
		<setting name="console_application" value="true"/>
		<library name="simple_cli" location="$SIMPLE_EIFFEL/simple_cli/simple_cli.ecf"/>
		<cluster name="stress" location=".\stress\"/>
			<!-- disk mode uses its own inline C with write-through (R-8); simple_file writes byte by byte -->
	</target>
	<!-- Phase 2 SHOULD (R-5): headless recorder, no window and no console -->
	<target name="taskman_recorder" extends="simple_taskman">
		<root class="TM_RECORDER_APP" feature="make"/>
		<setting name="console_application" value="false"/>
		<cluster name="recorder_app" location=".\recorder_app\"/>
	</target>
</system>
```
