# CONTRACT DESIGN: simple_taskman

Date: 2026-10-03

## Ground rules

1. **Invariants are O(1)** (C-011, oracle rule 2026-09-11). They compare
   scalars and counts. Anything that quantifies over a collection is a
   postcondition, usually through an MML model query.
2. **Every feature named in a precondition is exported** to every client of the
   routine (EIFFEL_EXPERT_BRIEFING, "Preconditions").
3. **Tests assert through TEST_SET_BASE**, never through `check` (finalized
   `check` is vacuous; memory note "Finalized check assertions vacuous").
4. **Contracts never call externals.** A postcondition that read the machine a
   second time would measure a different instant and fail at random.
5. **MML element equality is by value** (`MML_SET.has` uses `model_equals`,
   `simple_mml/src/mml_set.e:51-55`), so `TM_PROCESS_ID` with a redefined
   `is_equal` works inside models. `MML_MAP.has` tests a *value*; key tests use
   `domain.has` (survey of simple_mml).
6. A model query is a function that builds the model on every call. It is
   only ever used in postconditions and tests, never in an invariant or in
   implementation logic.
7. **Notation in this document:** a bare `Available`, `Unavailable`, and so on
   abbreviates `{TM_READING_STATUS}.Available`. `07-SPECIFICATION.md` writes
   the qualified form.
8. **Constant holders are reached only for constants.** EiffelStudio permits a
   non-object call `{CLASS}.feature` only when the feature is a constant or an
   external (error VUNO otherwise). So a classification such as "is this a
   known resource" is written as a range test on constants, for example
   `a_resource >= {TM_RESOURCE}.Cpu and a_resource <= {TM_RESOURCE}.Io_total`,
   never as `{TM_RESOURCE}.is_known (a_resource)`.

## MML Model Queries

| Class | Attribute | Type | Model Query | MML Type |
|-------|-----------|------|-------------|----------|
| `TM_READINGS` | `table` | `HASH_TABLE [TM_READING, STRING_8]` | `readings_model` | `MML_MAP [STRING_8, TM_READING]` |
| `TM_SNAPSHOT` | `samples` | `HASH_TABLE [TM_PROCESS_SAMPLE, TM_PROCESS_ID]` | `identities_model` | `MML_SET [TM_PROCESS_ID]` |
| `TM_FRAME` | `activity_table` | `HASH_TABLE [TM_PROCESS_ACTIVITY, TM_PROCESS_ID]` | `identities_model` | `MML_SET [TM_PROCESS_ID]` |
| `TM_FRAME` | `born_list` | `ARRAYED_LIST [TM_PROCESS_ID]` | `born_model` | `MML_SET [TM_PROCESS_ID]` |
| `TM_WINDOW` | `frame_list` | `ARRAYED_LIST [TM_FRAME]` | `frames_model` | `MML_SEQUENCE [TM_FRAME]` |
| `TM_SERIES` | ring of `SPECIAL`s | | `statuses_model` | `MML_SEQUENCE [INTEGER]` |
| `TM_CAPABILITIES` | `support` | `HASH_TABLE [INTEGER, INTEGER]` | `support_model` | `MML_MAP [INTEGER, INTEGER]` |
| `TM_VERDICT` | `evidence_list` | `ARRAYED_LIST [TM_EVIDENCE]` | `evidence_model` | `MML_SEQUENCE [TM_EVIDENCE]` |
| `TM_VERDICT` | `culprit_list` | `ARRAYED_LIST [TM_CULPRIT]` | `culprits_model` | `MML_SEQUENCE [TM_CULPRIT]` |
| `TM_DIAGNOSTICIAN` | `rules` | `ARRAYED_LIST [TM_RULE]` | `rules_model` | `MML_SEQUENCE [TM_RULE]` |
| `TM_MEMORY_TRACE_STORE` | `frames` | `ARRAYED_LIST [TM_FRAME]` | `frames_model` | `MML_SEQUENCE [TM_FRAME]` |

`TM_READINGS` keys are `metric_code.out + "|" + instance` in UTF-8. The key
function is the only place that format is decided.

## Class Contracts: model

### TM_READING

```eiffel
make_measured (a_value: REAL_64; a_metric: TM_METRIC)
    ensure
        available_when_accepted: a_metric.accepts (a_value) implies (is_available and value = a_value)
        invalid_otherwise: not a_metric.accepts (a_value) implies is_invalid

make_unavailable    ensure is_unavailable
make_not_supported  ensure is_not_supported
make_access_denied  ensure is_access_denied
make_invalid        ensure is_invalid

value: REAL_64
    require
        available: is_available
    ensure
        definition: Result = stored_value

status_name: STRING_8
    ensure
        named: not Result.is_empty

invariant
    status_known: status >= {TM_READING_STATUS}.Available and status <= {TM_READING_STATUS}.Invalid
    exactly_one_status: is_available xor (is_unavailable or is_not_supported or is_access_denied or is_invalid)
    value_only_when_available: not is_available implies stored_value = 0.0
    available_is_finite: is_available implies not (stored_value.is_nan or stored_value.is_positive_infinity or stored_value.is_negative_infinity)
```

There is deliberately no creation procedure `make_available (a_value)`. A
value can enter the system only through `make_measured`, which checks it
against its metric (DR-002). Decoding a recording uses
`make_measured` too, so a corrupted file cannot smuggle in an impossible
value.

### TM_METRIC

```eiffel
make (a_code: INTEGER; a_name: STRING_8; a_unit: STRING_8; a_label: STRING_32;
      a_minimum, a_maximum: REAL_64; a_is_instanced, a_is_peak: BOOLEAN)
    require
        code_positive: a_code > 0
        name_dotted_lowercase: is_valid_name (a_name)
        unit_given: not a_unit.is_empty
        ordered_range: a_minimum <= a_maximum
    ensure
        kept: code = a_code and name.is_equal (a_name) and minimum = a_minimum and maximum = a_maximum
        flags_kept: is_instanced = a_is_instanced and is_peak = a_is_peak

accepts (a_value: REAL_64): BOOLEAN
    ensure
        definition: Result = (not (a_value.is_nan or a_value.is_positive_infinity or a_value.is_negative_infinity)
                              and a_value >= minimum and a_value <= maximum)

invariant
    ordered_range: minimum <= maximum
    code_positive: code > 0
```

`is_peak` decides aggregation when frames merge: peak metrics (lag maximum)
take the maximum, all others take the duration-weighted mean.

### TM_METRICS (registry)

```eiffel
metric (a_code: INTEGER): TM_METRIC
    require
        known: has_code (a_code)
    ensure
        matches: Result.code = a_code

metric_named (a_name: READABLE_STRING_8): TM_METRIC
    require
        known: has_name (a_name)
    ensure
        matches: Result.name.same_string (a_name)

all_metrics: ARRAYED_LIST [TM_METRIC]
    ensure
        fresh: Result /= all_metrics_storage
        complete: Result.count = count

invariant
    codes_dense: count = Last_code    -- codes run 1..Last_code with no holes
```

The registry is built once per processor (`once` is per processor under
SCOOP) and never changes.

### TM_READINGS

```eiffel
put (a_code: INTEGER; a_instance: READABLE_STRING_32; a_reading: TM_READING)
    require
        open: not is_sealed
        known_metric: metrics.has_code (a_code)
        instance_rule: metrics.metric (a_code).is_instanced = not a_instance.is_empty
    ensure
        stored: reading (a_code, a_instance) = a_reading
        others_unchanged: readings_model |=| (old readings_model).updated (key (a_code, a_instance), a_reading)

reading (a_code: INTEGER; a_instance: READABLE_STRING_32): TM_READING
    require
        known_metric: metrics.has_code (a_code)
    ensure
        stored_if_present: has (a_code, a_instance) implies Result = readings_model [key (a_code, a_instance)]
        not_supported_if_absent: not has (a_code, a_instance) implies Result.is_not_supported

instances (a_code: INTEGER): ARRAYED_LIST [STRING_32]
    require
        instanced: metrics.metric (a_code).is_instanced
    ensure
        each_present: across Result as ic all has (a_code, ic) end

seal
    ensure
        sealed: is_sealed
        unchanged: readings_model |=| old readings_model

invariant
    count_matches_table: count = table.count
```

A sealed `TM_READINGS` is immutable. `TM_FRAME` seals its readings in its
creation procedure, so a frame handed to a view cannot be edited.

### TM_PROCESS_ID

```eiffel
make (a_pid, a_creation_ticks: INTEGER_64)
    require
        pid_non_negative: a_pid >= 0
        creation_non_negative: a_creation_ticks >= 0
    ensure
        kept: pid = a_pid and creation_ticks = a_creation_ticks

is_equal (other: like Current): BOOLEAN
    ensure then
        both_fields: Result = (pid = other.pid and creation_ticks = other.creation_ticks)

hash_code: INTEGER
    ensure then
        non_negative: Result >= 0      -- inherited guarantee restated

invariant
    pid_non_negative: pid >= 0
    creation_non_negative: creation_ticks >= 0
```

The idle pseudo-process has creation time 0 in the native table; the
invariant allows it, and `is_idle_pseudo_process` names it.

### TM_PROCESS_SAMPLE

```eiffel
make (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32; a_parent_pid: INTEGER_64; a_session: INTEGER)
    ensure
        identity_kept: id ~ a_id
        name_copied: name.same_string (a_name) and name /= a_name
        groups_unset: cpu_status = {TM_READING_STATUS}.Unavailable
                      and memory_status = {TM_READING_STATUS}.Unavailable
                      and io_status = {TM_READING_STATUS}.Unavailable

set_cpu (a_user_ticks, a_kernel_ticks: INTEGER_64)
    require
        not_yet: cpu_status = {TM_READING_STATUS}.Unavailable
        non_negative: a_user_ticks >= 0 and a_kernel_ticks >= 0
    ensure
        available: cpu_status = {TM_READING_STATUS}.Available
        kept: user_ticks = a_user_ticks and kernel_ticks = a_kernel_ticks
        others_unchanged: memory_status = old memory_status and io_status = old io_status

deny_cpu (a_status: INTEGER)     -- access denied, not supported, or invalid
    require
        not_yet: cpu_status = {TM_READING_STATUS}.Unavailable
        a_reason: a_status /= {TM_READING_STATUS}.Available
    ensure
        kept: cpu_status = a_status

-- set_memory / deny_memory and set_io / deny_io follow the same shape.

user_ticks: INTEGER_64       require cpu_status = {TM_READING_STATUS}.Available
working_set: INTEGER_64      require memory_status = {TM_READING_STATUS}.Available
read_bytes: INTEGER_64       require io_status = {TM_READING_STATUS}.Available
```

The three groups follow what the sources can actually deliver: the native
table gives all three at once; the documented fallback can be denied any of
them per process.

### TM_PROCESS_ACTIVITY

```eiffel
make_from_pair (a_before, a_after: TM_PROCESS_SAMPLE; a_seconds: REAL_64; a_logical_processors: INTEGER)
    require
        same_identity: a_before.id ~ a_after.id                          -- DR-004
        positive_time: a_seconds > 0.0
        processors: a_logical_processors > 0
        not_idle: not a_after.id.is_idle_pseudo_process                  -- A-111
    ensure
        identity_kept: id ~ a_after.id
        cpu_when_both: (a_before.cpu_status = Available and a_after.cpu_status = Available
                        and cpu_cores <= a_logical_processors * Cpu_tolerance)
                        implies cpu_status = Available
        cpu_invalid_when_impossible: cpu_status = Available implies cpu_cores <= a_logical_processors * Cpu_tolerance
        not_new: not is_new

make_born (a_after: TM_PROCESS_SAMPLE)
    ensure
        new: is_new
        no_rates: cpu_status = {TM_READING_STATUS}.Unavailable and io_status = {TM_READING_STATUS}.Unavailable

cpu_cores: REAL_64            require cpu_status = Available    ensure Result >= 0.0
cpu_percent: REAL_64          require cpu_status = Available    ensure Result >= 0.0
io_read_bps, io_write_bps     require io_status = Available     ensure Result >= 0.0

invariant
    cpu_percent_consistent: cpu_status = {TM_READING_STATUS}.Available implies
        (cpu_percent - cpu_cores * 100.0 / logical_processors).abs < 0.000_001
```

A counter that went *down* between two samples of the same identity is
impossible; that group's status becomes invalid rather than a negative rate.
`Cpu_tolerance = 1.05` absorbs sampling jitter at the edge (DR-008).

### TM_FRAME

```eiffel
make (a_start, a_end, a_duration: INTEGER_64; a_logical_processors: INTEGER;
      a_readings: TM_READINGS; a_activities: ITERABLE [TM_PROCESS_ACTIVITY];
      a_born: ITERABLE [TM_PROCESS_ID]; a_exited: ITERABLE [TM_PROCESS_SAMPLE])
    require
        ordered: a_end > a_start                                         -- DR-005
        positive_duration: a_duration > 0
        processors: a_logical_processors > 0
        no_idle: across a_activities as ic all not ic.id.is_idle_pseudo_process end
    ensure
        times_kept: start_ticks = a_start and end_ticks = a_end and duration = a_duration
        sealed: readings.is_sealed
        complete: is_complete and omitted_processes = 0
        live: not is_discontinuity

make_discontinuity (a_start, a_end, a_duration: INTEGER_64; a_logical_processors: INTEGER;
                    a_supported: ITERABLE [INTEGER])
    require
        ordered: a_end > a_start
        positive_duration: a_duration > 0
        processors: a_logical_processors > 0
        known_metrics: across a_supported as ic all metrics.has_code (ic) end
    ensure
        flagged: is_discontinuity
        empty: activity_count = 0
        all_unavailable: across a_supported as ic all
                             not metrics.metric (ic).is_instanced implies readings.reading (ic, "").is_unavailable end

activity (a_id: TM_PROCESS_ID): TM_PROCESS_ACTIVITY
    require
        present: has_activity (a_id)
    ensure
        matches: Result.id ~ a_id

activities: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
    ensure
        fresh_each_call: Result /= activities     -- FR-057: views get their own list
        complete: Result.count = activity_count

top_by (a_resource, a_count: INTEGER): ARRAYED_LIST [TM_PROCESS_ACTIVITY]
    require
        known_resource: a_resource >= {TM_RESOURCE}.Cpu and a_resource <= {TM_RESOURCE}.Io_total
        positive: a_count > 0
    ensure
        bounded: Result.count <= a_count
        measured_only: across Result as ic all ic.has_resource (a_resource) end
        descending: across 2 |..| Result.count as ic all
                        Result [ic - 1].amount_of (a_resource) >= Result [ic].amount_of (a_resource) end

invariant
    ordered: end_ticks > start_ticks
    positive_duration: duration > 0
    processors: logical_processors > 0
    discontinuity_is_empty: is_discontinuity implies activity_count = 0
    recorded_subset: is_complete implies omitted_processes = 0
```

**Why `a_supported`.** Reading lookup defaults to *not supported* for anything
absent (`TM_READINGS.reading`). For a discontinuity that is the wrong reason:
the sensor exists, the tool was simply not measuring. So the discontinuity
frame stores an explicit *unavailable* reading for every metric the source
supports.

### TM_WINDOW

```eiffel
extend (a_frame: TM_FRAME)
    require
        in_order: not is_empty implies a_frame.start_ticks >= last_frame.end_ticks      -- DR-006, O(1)
    ensure
        appended: frames_model |=| (old frames_model) & a_frame
        new_end: end_ticks = a_frame.end_ticks
        first_sets_start: old is_empty implies start_ticks = a_frame.start_ticks
        start_kept: not old is_empty implies start_ticks = old start_ticks

aggregate (a_code: INTEGER; a_instance: READABLE_STRING_32): TM_AGGREGATE
    require
        not_empty: not is_empty
        known_metric: metrics.has_code (a_code)
    ensure
        coverage_bounded: Result.coverage >= 0.0 and Result.coverage <= 1.0
        unavailable_when_unmeasured: Result.coverage = 0.0 implies not Result.reading.is_available
        peak_rule: metrics.metric (a_code).is_peak implies Result.kind = {TM_AGGREGATE}.Peak
        mean_rule: not metrics.metric (a_code).is_peak implies Result.kind = {TM_AGGREGATE}.Weighted_mean

ranked (a_resource: INTEGER; a_count: INTEGER): ARRAYED_LIST [TM_PROCESS_TOTAL]
    require
        not_empty: not is_empty
        known_resource: a_resource >= {TM_RESOURCE}.Cpu and a_resource <= {TM_RESOURCE}.Io_total
        positive: a_count > 0
    ensure
        bounded: Result.count <= a_count
        descending: across 2 |..| Result.count as ic all Result [ic - 1].total >= Result [ic].total end

measured_seconds: REAL_64
    ensure
        within_span: Result <= (end_ticks - start_ticks) / Ticks_per_second + Epsilon

invariant
    empty_has_no_span: is_empty implies (start_ticks = 0 and end_ticks = 0)
    span_ordered: not is_empty implies end_ticks > start_ticks
    count_matches: count = frame_list.count
```

Coverage is measured duration over window span, where a frame counts as
measured for a metric when its reading is available. Discontinuity frames
add span but never coverage, which is how a sleeping laptop stays honest in
every aggregate.

### TM_SERIES

```eiffel
make (a_capacity: INTEGER)
    require
        positive: a_capacity > 0
    ensure
        empty: count = 0
        capacity_kept: capacity = a_capacity

extend (a_ticks: INTEGER_64; a_reading: TM_READING)
    require
        in_order: count > 0 implies a_ticks > last_ticks
    ensure
        bounded: count = (old count + 1).min (capacity)
        newest_status: status_at (count) = a_reading.status
        newest_value: a_reading.is_available implies value_at (count) = a_reading.value
        history_kept: old count < capacity implies statuses_model.front (old count) |=| old statuses_model
        oldest_dropped: old count = capacity implies statuses_model.front (count - 1) |=| (old statuses_model).but_first

value_at (i: INTEGER): REAL_64
    require
        in_range: i >= 1 and i <= count
        available: is_available_at (i)

invariant
    bounded: count <= capacity
    non_negative: count >= 0
```

### TM_CLOCK (deferred)

```eiffel
utc_ticks: INTEGER_64
    deferred
    ensure
        after_1601: Result > 0

monotonic_ticks: INTEGER_64
    deferred
    ensure
        non_negative: Result >= 0
```

"Never runs backward" is a property of a *sequence* of calls. Stating it as a
postcondition would force the query to remember its last answer, a side
effect in a query. So it is enforced where it matters, as the precondition
`ordered` of `TM_FRAME_BUILDER.build`, and tested directly on
`TM_SYSTEM_CLOCK` with a tight loop of reads.

`TM_MANUAL_CLOCK.advance (a_ticks)` requires `a_ticks >= 0`; `set_utc`
may move UTC backward (to test A-109) but never the monotonic counter.

## Class Contracts: probe

### TM_PROCESS_SOURCE (deferred)

```eiffel
read_all
    require
        trusted: is_trusted
        open: not is_closed
    deferred
    ensure
        succeeded_or_said_why: last_read_succeeded xor not last_error.is_empty
        idle_present_when_native: (last_read_succeeded and is_native) implies has_idle_entry
        unique_identities: last_read_succeeded implies samples_model.count = last_samples.count

last_samples: ARRAYED_LIST [TM_PROCESS_SAMPLE]
    require
        read: last_read_succeeded
    ensure
        fresh: Result /= last_samples

is_trusted: BOOLEAN
    -- For the native source: the layout self-check passed. Documented and scripted sources: always True.
```

### TM_NATIVE_PROCESS_SOURCE

```eiffel
make
    ensure
        checked: self_check_ran
        trusted_only_if_passed: is_trusted = last_self_check.passed
        reason_when_untrusted: not is_trusted implies not last_self_check.failure.is_empty
        not_64_bit_never_trusted: not {PLATFORM}.is_64_bits implies not is_trusted
        located_or_untrusted: query_function = default_pointer implies not is_trusted

invariant
    buffer_present: buffer.count >= Minimum_buffer_bytes
    trusted_has_function: is_trusted implies query_function /= default_pointer
```

`SIMPLE_TASKMAN.make` chooses: native if trusted, otherwise documented, and
records the self-check failure text in `capabilities` so the owner sees why.

### TM_SYSTEM_SOURCE (deferred)

```eiffel
refresh
    require
        open: not is_closed
    deferred
    ensure
        sealed: last_readings.is_sealed
        unsupported_reads_as_declared: across metrics.codes as ic all
             (support_of (ic) /= Available and not metrics.metric (ic).is_instanced)
                 implies last_readings.reading (ic, "").status = support_of (ic) end

support_of (a_code: INTEGER): INTEGER
    require
        known_metric: metrics.has_code (a_code)
    ensure
        known_status: Result >= {TM_READING_STATUS}.Available and Result <= {TM_READING_STATUS}.Invalid
        stable: Result = support_of (a_code)       -- support is decided at creation and never changes
```

Support is decided once, at creation, by trying each counter. On this
machine that yields temperature not supported and package power available.
The first `refresh` after creation reports rate counters as unavailable,
because PDH needs two collections for a rate.

### TM_COUNTER_QUERY

```eiffel
add_english (a_path: READABLE_STRING_GENERAL): INTEGER
    require
        open: not is_closed
        path_given: not a_path.is_empty
    ensure
        added_or_zero: (Result > 0) = (last_status = Pdh_ok)
        counted: Result > 0 implies counter_count = old counter_count + 1

collect
    require
        open: not is_closed
        has_counters: counter_count > 0
    ensure
        collected: collections = old collections + 1

values (a_counter: INTEGER): ARRAYED_LIST [TM_COUNTER_VALUE]
    require
        valid_counter: a_counter >= 1 and a_counter <= counter_count
        collected_twice_for_rates: collections >= 1
    ensure
        fresh: Result /= values (a_counter)

close
    ensure
        closed: is_closed
```

`TM_COUNTER_VALUE.is_valid` is true only for PDH status valid or new data;
the system source turns anything else into an invalid reading.

## Class Contracts: sampling

### TM_FRAME_BUILDER

```eiffel
build (a_previous, a_current: TM_SNAPSHOT; a_logical_processors: INTEGER;
       a_self: TM_PROCESS_ID; a_previous_cost: INTEGER_64): TM_FRAME
    require
        ordered: a_current.monotonic_ticks > a_previous.monotonic_ticks
        processors: a_logical_processors > 0
    ensure
        span: Result.start_ticks = a_previous.utc_ticks and Result.end_ticks = a_current.utc_ticks
                 -- when UTC went backward (A-109), end_ticks = start_ticks + duration instead
        duration: Result.duration = a_current.monotonic_ticks - a_previous.monotonic_ticks
        every_current_process: Result.identities_model |=| (a_current.identities_model - idle_set)
                 -- every current identity except idle is an activity; survivors have rates, newcomers are born
        born: Result.born_model |=| (a_current.identities_model - a_previous.identities_model - idle_set)
        exited_count: Result.exited.count = (a_previous.identities_model - a_current.identities_model - idle_set).count
        no_rate_across_identities: across Result.activities as ic all
                 ic.is_new = not a_previous.identities_model.has (ic.id) end
```

The `no_rate_across_identities` clause is FR-003's recycled-pid test written
as a contract: a process whose pid existed before under a different creation
time is *born*, never given a rate from its predecessor.

### TM_SAMPLER

```eiffel
sample
    ensure
        snapshot_taken: has_snapshot and snapshots_taken = old snapshots_taken + 1
        frame_after_first: (old has_snapshot) = has_frame
        counted: has_frame implies frames_made = old frames_made + 1
        gap_detected: has_frame and then last_frame.is_discontinuity implies discontinuities = old discontinuities + 1
        cost_measured: last_tick_cost >= 0

set_nominal_interval (a_ticks: INTEGER_64)
    require
        sane: a_ticks >= Minimum_interval and a_ticks <= Maximum_interval
    ensure
        kept: nominal_interval = a_ticks

invariant
    frames_bounded: frames_made >= discontinuities
    interval_sane: nominal_interval >= Minimum_interval and nominal_interval <= Maximum_interval
```

### TM_SELF_BUDGET

```eiffel
make (a_cpu_bound_pct: REAL_64; a_minimum_ms, a_maximum_ms: INTEGER)
    require
        bound_positive: a_cpu_bound_pct > 0.0
        ordered: 0 < a_minimum_ms and a_minimum_ms <= a_maximum_ms
    ensure
        starts_fast: interval_ms = a_minimum_ms

assess (a_tick_cost, a_interval: INTEGER_64)
        -- Judge one tick: `a_tick_cost' monotonic ticks spent sampling out of
        -- an `a_interval' of nominal ticks (R-1, intent Q3).
    require
        cost_non_negative: a_tick_cost >= 0
        interval_positive: a_interval > 0
    ensure
        share_recorded: last_share_pct = a_tick_cost * 100.0 / a_interval
        within_bounds: interval_ms >= minimum_ms and interval_ms <= maximum_ms
        backs_off: (over_streak >= Over_limit and old interval_ms < maximum_ms) implies interval_ms > old interval_ms
        never_speeds_up_while_over: last_share_pct > cpu_bound_pct implies interval_ms >= old interval_ms
        logged_on_change: interval_ms /= old interval_ms implies changes = old changes + 1

invariant
    within_bounds: interval_ms >= minimum_ms and interval_ms <= maximum_ms
```

The budget governs **sampling cost only**: time spent in `sample` as a share
of the nominal interval, a percent of one logical processor, matching
NFR-001's wording. Backing off then reduces exactly what was measured.
Whole-process CPU (`self.cpu_pct`, which includes GUI rendering) is still a
displayed reading, but the budget does not chase it, because a longer
sampling interval cannot reduce rendering cost (intent Q3).

## Class Contracts: handoff

### TM_FRAME_CODEC

```eiffel
encode (a_frame: TM_FRAME): STRING_8
    ensure
        versioned: Result.starts_with (Header)
        decodable: is_well_formed (Result)

decode (a_text: READABLE_STRING_8)
    ensure
        decoded_or_said_why: has_frame xor not last_error.is_empty
        round_trip_shape: has_frame implies last_frame.activity_count = activity_count_in (a_text)

is_well_formed (a_text: READABLE_STRING_8): BOOLEAN
    -- Header, record tags, field counts. Never raises.
```

Values travel as the hexadecimal image of their 64 bits, so encode then
decode is exact (DR-018, FR-NEW-006), and every decoded value passes back
through `make_measured`. Text fields are UTF-8 with tab, newline, and
backslash escaped.

### TM_FRAME_SLOT

```eiffel
put_frame (a_text: separate READABLE_STRING_8)
    require
        given: not a_text.is_empty
    ensure
        ready: has_frame
        counted: deposited = old deposited + 1
        dropped_if_unread: (old has_frame) implies dropped = old dropped + 1
        copy_owned: frame_text.same_string (a_text)     -- copied; nothing of the worker's is held

clear
    ensure
        taken: not has_frame

request_stop
    ensure
        requested: stop_requested

invariant
    counts_non_negative: deposited >= 0 and dropped >= 0
    dropped_bounded: dropped <= deposited
```

Every routine is a field read or assignment, so a call from the GUI never
waits on sampling (FR-056). This is the property simple_chat's
`SUMMARY_SLOT` documents as "NEVER blocks".

### TM_SAMPLING_WORKER

```eiffel
attach_slot (a_slot: separate TM_FRAME_SLOT)
    require
        not_running: not is_running
    ensure
        attached_slot: slot = a_slot

run
    require
        has_slot: attached slot
        not_running: not is_running
    ensure
        stopped: not is_running
```

`run` loops until `should_stop (slot)` answers True, so its postcondition
holds only after the GUI requests a stop. Its loop invariant: the slot is
never locked across a sample, a sleep, or a store commit.

## Class Contracts: facade

### SIMPLE_TASKMAN

```eiffel
make
    ensure
        nothing_sampled: not has_frame
        source_known: process_source_kind.same_string ("native") or process_source_kind.same_string ("documented")
        native_only_when_trusted: process_source_kind.same_string ("native") implies native_self_check_passed
        fallback_says_why: process_source_kind.same_string ("documented") implies not fallback_reason.is_empty
        no_store: not has_store
        open: not is_closed

make_with_sources (a_processes: TM_PROCESS_SOURCE; a_system: TM_SYSTEM_SOURCE; a_clock: TM_CLOCK)
    require
        trusted: a_processes.is_trusted
    ensure
        nothing_sampled: not has_frame

sample
    require
        open: not is_closed
    ensure
        frame_after_first: (old sampler.has_snapshot) implies has_frame
        recorded_when_storing: (has_store and has_frame) implies store.appended = old store.appended + 1

last_frame: TM_FRAME
    require
        has_frame: has_frame

set_nominal_interval (a_ms: INTEGER): like Current
    require
        sane: a_ms >= 250 and a_ms <= 60_000
    ensure
        result_current: Result = Current

diagnose (a_window: TM_WINDOW): TM_VERDICT          -- P3
    require
        not_empty: not a_window.is_empty
    ensure
        within_window: Result.window_start = a_window.start_ticks and Result.window_end = a_window.end_ticks

close
    ensure
        closed: is_closed
```

## Class Contracts: diagnosis (P3)

### TM_VERDICT

```eiffel
make_found (a_kind: INTEGER; a_culprits: ITERABLE [TM_CULPRIT]; a_sentence: READABLE_STRING_32;
            a_evidence: ITERABLE [TM_EVIDENCE]; a_confidence: INTEGER; a_window: TM_WINDOW)
    require
        real_kind: a_kind >= {TM_BOTTLENECK_KIND}.First_bottleneck and a_kind <= {TM_BOTTLENECK_KIND}.Last_bottleneck
        has_evidence: across a_evidence as ic some True end           -- at least one
        evidence_in_window: across a_evidence as ic all a_window.contains_span (ic.from_ticks, ic.to_ticks) end
        sentence_given: not a_sentence.is_empty
        known_confidence: a_confidence >= Confidence_low and a_confidence <= Confidence_high
    ensure
        found: is_found and kind = a_kind

make_none (a_window: TM_WINDOW)          ensure kind = {TM_BOTTLENECK_KIND}.None
make_inconclusive (a_window: TM_WINDOW; a_reason: READABLE_STRING_32)
    require reason_given: not a_reason.is_empty
    ensure kind = {TM_BOTTLENECK_KIND}.Inconclusive

invariant
    found_has_evidence: is_found implies evidence_count > 0                  -- DR-010
    nothing_blamed_without_finding: not is_found implies culprit_count = 0   -- DR-011
    window_ordered: window_end > window_start
    inconclusive_explains: kind = {TM_BOTTLENECK_KIND}.Inconclusive implies not reason.is_empty
```

### TM_RULE (deferred)

```eiffel
can_judge (a_window: TM_WINDOW): BOOLEAN
    ensure
        definition: Result = across required_metrics as ic all
                              a_window.aggregate (ic, "").coverage >= thresholds.minimum_coverage end
                         and a_window.measured_seconds >= thresholds.minimum_seconds

judge (a_window: TM_WINDOW): TM_VERDICT
    require
        judgeable: can_judge (a_window)
    deferred
    ensure
        own_kind_or_none: Result.kind = kind or Result.kind = {TM_BOTTLENECK_KIND}.None
        same_window: Result.window_start = a_window.start_ticks
        pure: a_window.frames_model |=| old a_window.frames_model
```

### TM_DIAGNOSTICIAN

```eiffel
diagnose (a_window: TM_WINDOW): TM_VERDICT
    require
        not_empty: not a_window.is_empty
    ensure
        inconclusive_when_none_can_judge: (across rules as ic all not ic.can_judge (a_window) end)
                                          implies Result.kind = {TM_BOTTLENECK_KIND}.Inconclusive
        precedence: Result.is_found implies
                       across rules as ic all
                           (ic.can_judge (a_window) and then ic.judge (a_window).is_found)
                           implies precedence (Result.kind) >= precedence (ic.kind) end
        pure: a_window.frames_model |=| old a_window.frames_model
```

The `precedence` clause re-runs every rule. That is why it is a
postcondition, which test builds keep, and never an invariant.

## Class Contracts: action (P4, signatures only)

```eiffel
TM_RESTRAINT.apply (a_handle: TM_PROCESS_HANDLE): TM_ACTION_OUTCOME
    require
        verified: a_handle.is_identity_verified          -- DR-014, checked on the open handle
        not_protected: not protected_set.has (a_handle.id) -- DR-015
        not_applied: not is_applied
    ensure
        receipt_on_success: Result.succeeded implies (is_applied and has_prior_state)

TM_RESTRAINT.undo (a_handle: TM_PROCESS_HANDLE): TM_ACTION_OUTCOME
    require
        applied: is_applied
        same_process: a_handle.id ~ target
    ensure
        restored_exactly: Result.succeeded implies current_state (a_handle) = prior_state   -- DR-016
```

## Contract Completeness Checklist

| Command | What changed? | How, relative to old? | What did not change? |
|---------|---------------|------------------------|----------------------|
| `TM_READINGS.put` | one key | `updated` on the old map | every other key (map frame) |
| `TM_READINGS.seal` | sealed flag | False to True | `readings_model` |
| `TM_PROCESS_SAMPLE.set_cpu` | CPU group | Unavailable to Available | memory and IO statuses |
| `TM_WINDOW.extend` | frames | old sequence `&` frame | earlier frames (sequence frame) |
| `TM_SERIES.extend` | newest entry | appended; oldest dropped at capacity | remaining history |
| `TM_SAMPLER.sample` | snapshot, frame, counters | counters +1 | nominal interval |
| `TM_SELF_BUDGET.assess` | interval, streaks | bounded change | interval when unmeasured |
| `TM_FRAME_SLOT.put_frame` | text, counters | deposited +1, dropped +1 if unread | stop flag |
| `TM_FRAME_SLOT.request_stop` | stop flag | set | frame text and counters |
| `TM_COUNTER_QUERY.add_english` | counter list | +1 on success | nothing on failure |
| `SIMPLE_TASKMAN.sample` | sampler state; store when attached | appended +1 | configuration |
| `TM_RESTRAINT.undo` (P4) | process attribute | back to prior state | everything else about the process |

Queries that must not change state (`TM_WINDOW.aggregate`, `TM_RULE.judge`,
`TM_DIAGNOSTICIAN.diagnose`) state `pure` with a model frame condition.
