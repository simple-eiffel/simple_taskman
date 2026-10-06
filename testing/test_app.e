note
	description: "[
		Console test runner for simple_taskman.

		Phase 1 (contracts) state: every library class exists with its full
		contracts, but behaviour the spec leaves as a comment is a Phase 4
		stub. Tests of that behaviour are written now from the contracts and
		are expected to FAIL until Phase 4 implements it; the run reports them
		honestly instead of hiding them. Output is flushed after every line,
		so a crash still shows the last test that started.
	]"
	author: "Larry Rix"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run every test set.
		do
			say ("Running simple_taskman tests...%N")
			run_reading_tests
			run_process_id_tests
			run_readings_tests
			run_activity_tests
			run_frame_tests
			run_sampler_tests
			run_window_tests
			run_codec_tests
			run_budget_format_tests
			run_source_tests
			run_slot_tests
			run_lib_tests
			run_coverage_model_tests
			run_coverage_probe_tests
			run_codec_robustness_tests
			run_worker_tests
			run_harden_scale_tests
			run_harden_input_tests
			run_harden_scoop_tests
			run_target_tests
			run_recorder_tests
			run_harden_recorder_tests
			run_control_tests
			run_performance_tests
			run_settings_tests
			run_services_tests
			run_startup_tests
			run_acceptance_tests
			say ("%N========================%N")
			say ("Results: " + passed.out + " passed, " + failed.out + " failed%N")
			if failed > 0 then
				say ("TESTS FAILED%N")
			else
				say ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- Test sets

	run_reading_tests
		local
			t: TEST_READING
		do
			section ("reading and metrics")
			create t
			run_test (agent t.test_measured_inside_range_is_available, "measured_inside_range_is_available")
			run_test (agent t.test_measured_outside_range_is_invalid, "measured_outside_range_is_invalid")
			run_test (agent t.test_non_finite_is_invalid, "non_finite_is_invalid")
			run_test (agent t.test_status_names_are_words, "status_names_are_words")
			run_test (agent t.test_value_of_missing_reading_is_refused, "value_of_missing_reading_is_refused")
			run_test (agent t.test_catalog_is_dense, "catalog_is_dense")
			run_test (agent t.test_names_are_valid_and_unique, "names_are_valid_and_unique")
			run_test (agent t.test_valid_name_rules, "valid_name_rules")
			run_test (agent t.test_only_peak_metrics_aggregate_by_maximum, "only_peak_metrics_aggregate_by_maximum")
		end

	run_process_id_tests
		local
			t: TEST_PROCESS_ID
		do
			section ("process identity and samples")
			create t
			run_test (agent t.test_recycled_pid_is_another_process, "recycled_pid_is_another_process")
			run_test (agent t.test_equal_identities_hash_equal, "equal_identities_hash_equal")
			run_test (agent t.test_idle_pseudo_process, "idle_pseudo_process")
			run_test (agent t.test_identity_works_as_table_key, "identity_works_as_table_key")
			run_test (agent t.test_groups_start_unset, "groups_start_unset")
			run_test (agent t.test_setting_one_group_leaves_the_others, "setting_one_group_leaves_the_others")
			run_test (agent t.test_a_group_is_set_once, "a_group_is_set_once")
			run_test (agent t.test_denied_group_has_no_number, "denied_group_has_no_number")
		end

	run_readings_tests
		local
			t: TEST_READINGS
		do
			section ("readings")
			create t
			run_test (agent t.test_absent_reads_not_supported, "absent_reads_not_supported")
			run_test (agent t.test_put_then_read, "put_then_read")
			run_test (agent t.test_instances_in_insertion_order, "instances_in_insertion_order")
			run_test (agent t.test_sealed_refuses_put, "sealed_refuses_put")
			run_test (agent t.test_instance_rule, "instance_rule")
			run_test (agent t.test_value_filed_under_the_wrong_metric_refused, "value_filed_under_the_wrong_metric_refused")
			run_test (agent t.test_reading_with_wrong_instance_form_refused, "reading_with_wrong_instance_form_refused")
			run_test (agent t.test_put_frame_condition_in_mml, "put_frame_condition_in_mml")
			run_test (agent t.test_make_from_copies_and_reopens, "make_from_copies_and_reopens")
		end

	run_activity_tests
		local
			t: TEST_ACTIVITY
		do
			section ("process activity")
			create t
			run_test (agent t.test_born_has_no_rates, "born_has_no_rates")
			run_test (agent t.test_one_core_for_two_seconds, "one_core_for_two_seconds")
			run_test (agent t.test_counter_running_backward_is_invalid, "counter_running_backward_is_invalid")
			run_test (agent t.test_impossible_rate_is_invalid_not_clamped, "impossible_rate_is_invalid_not_clamped")
			run_test (agent t.test_missing_group_keeps_the_more_useful_reason, "missing_group_keeps_the_more_useful_reason")
			run_test (agent t.test_rate_across_identities_refused, "rate_across_identities_refused")
			run_test (agent t.test_worse_of_order, "worse_of_order")
		end

	run_frame_tests
		local
			t: TEST_FRAME
		do
			section ("frame and frame builder")
			create t
			run_test (agent t.test_make_seals_readings, "make_seals_readings")
			run_test (agent t.test_activities_is_a_fresh_list, "activities_is_a_fresh_list")
			run_test (agent t.test_discontinuity_reads_unavailable_not_unsupported, "discontinuity_reads_unavailable_not_unsupported")
			run_test (agent t.test_decoded_frame_is_incomplete, "decoded_frame_is_incomplete")
			run_test (agent t.test_backward_frame_refused, "backward_frame_refused")
			run_test (agent t.test_top_by_cpu_is_descending_and_measured, "top_by_cpu_is_descending_and_measured")
			run_test (agent t.test_survivor_gets_a_rate, "survivor_gets_a_rate")
			run_test (agent t.test_recycled_pid_is_born_not_rated, "recycled_pid_is_born_not_rated")
			run_test (agent t.test_idle_is_left_out, "idle_is_left_out")
			run_test (agent t.test_self_readings_added, "self_readings_added")
		end

	run_sampler_tests
		local
			t: TEST_SAMPLER
		do
			section ("sampler")
			create t
			run_test (agent t.test_first_sample_makes_no_frame, "first_sample_makes_no_frame")
			run_test (agent t.test_second_sample_makes_a_frame, "second_sample_makes_a_frame")
			run_test (agent t.test_gap_makes_a_discontinuity, "gap_makes_a_discontinuity")
			run_test (agent t.test_failed_process_read_keeps_going, "failed_process_read_keeps_going")
			run_test (agent t.test_interval_outside_bounds_refused, "interval_outside_bounds_refused")
			run_test (agent t.test_cost_is_measured_on_the_clock, "cost_is_measured_on_the_clock")
			run_test (agent t.test_clock_change_rule, "clock_change_rule")
			run_test (agent t.test_clock_set_back_keeps_frames_ordered, "clock_set_back_keeps_frames_ordered")
			run_test (agent t.test_clock_set_forward_returns_to_wall_time, "clock_set_forward_returns_to_wall_time")
		end

	run_window_tests
		local
			t: TEST_WINDOW
		do
			section ("window and series")
			create t
			run_test (agent t.test_extend_sets_the_span, "extend_sets_the_span")
			run_test (agent t.test_out_of_order_frame_refused, "out_of_order_frame_refused")
			run_test (agent t.test_mean_is_weighted_by_duration, "mean_is_weighted_by_duration")
			run_test (agent t.test_discontinuity_adds_span_not_coverage, "discontinuity_adds_span_not_coverage")
			run_test (agent t.test_unmeasured_metric_has_zero_coverage, "unmeasured_metric_has_zero_coverage")
			run_test (agent t.test_peak_metric_takes_the_maximum, "peak_metric_takes_the_maximum")
			run_test (agent t.test_extend_frame_condition_in_mml, "extend_frame_condition_in_mml")
			run_test (agent t.test_ranked_totals_by_identity, "ranked_totals_by_identity")
			run_test (agent t.test_new_series_is_empty, "new_series_is_empty")
			run_test (agent t.test_extend_keeps_value_and_gap, "extend_keeps_value_and_gap")
			run_test (agent t.test_full_series_drops_the_oldest, "full_series_drops_the_oldest")
		end

	run_codec_tests
		local
			t: TEST_CODEC
		do
			section ("frame codec")
			create t
			run_test (agent t.test_round_trip_is_exact, "round_trip_is_exact")
			run_test (agent t.test_unknown_header_is_refused_with_the_line, "unknown_header_is_refused_with_the_line")
			run_test (agent t.test_impossible_value_decodes_as_invalid, "impossible_value_decodes_as_invalid")
			run_test (agent t.test_activity_lines_counted, "activity_lines_counted")
			run_test (agent t.test_capabilities_round_trip, "capabilities_round_trip")
			run_test (agent t.test_round_trip_with_activities, "round_trip_with_activities")
			run_test (agent t.test_frame_texts_split, "frame_texts_split")
		end

	run_budget_format_tests
		local
			t: TEST_BUDGET_FORMAT
		do
			section ("self-budget and format")
			create t
			run_test (agent t.test_budget_starts_fast, "budget_starts_fast")
			run_test (agent t.test_share_is_cost_over_interval, "share_is_cost_over_interval")
			run_test (agent t.test_backs_off_after_three_ticks_over, "backs_off_after_three_ticks_over")
			run_test (agent t.test_never_exceeds_the_maximum, "never_exceeds_the_maximum")
			run_test (agent t.test_speeds_up_after_a_quiet_spell, "speeds_up_after_a_quiet_spell")
			run_test (agent t.test_missing_reading_is_words_for_every_status, "missing_reading_is_words_for_every_status")
			run_test (agent t.test_watts, "watts")
			run_test (agent t.test_bytes_are_scaled, "bytes_are_scaled")
			run_test (agent t.test_percent_and_cores, "percent_and_cores")
			run_test (agent t.test_status_words_are_not_numbers, "status_words_are_not_numbers")
		end

	run_source_tests
		local
			t: TEST_SOURCES
		do
			section ("probe sources")
			create t
			run_test (agent t.test_scripted_process_rounds_in_order, "scripted_process_rounds_in_order")
			run_test (agent t.test_scripted_system_reads_as_declared, "scripted_system_reads_as_declared")
			run_test (agent t.test_support_is_fixed_after_first_refresh, "support_is_fixed_after_first_refresh")
			run_test (agent t.test_flat_index_across_groups, "flat_index_across_groups")
			run_test (agent t.test_hybrid_detected, "hybrid_detected")
			run_test (agent t.test_heatmap_shapes, "heatmap_shapes")
			run_test (agent t.test_paths_under_a_base, "paths_under_a_base")
			run_test (agent t.test_unsafe_log_name_refused, "unsafe_log_name_refused")
			run_test (agent t.test_live_root_is_under_localappdata, "live_root_is_under_localappdata")
			run_test (agent t.test_native_self_check_is_decided, "native_self_check_is_decided")
			run_test (agent t.test_documented_read_lists_self, "documented_read_lists_self")
			run_test (agent t.test_win_processor_count_matches_windows, "win_processor_count_matches_windows")
			run_test (agent t.test_live_topology_counts_all_groups, "live_topology_counts_all_groups")
			run_test (agent t.test_pdh_adds_a_real_counter, "pdh_adds_a_real_counter")
			run_test (agent t.test_pdh_refuses_a_bad_path, "pdh_refuses_a_bad_path")
			run_test (agent t.test_pdh_two_collections_give_values, "pdh_two_collections_give_values")
			run_test (agent t.test_pdh_close_twice_is_safe, "pdh_close_twice_is_safe")
			run_test (agent t.test_second_refresh_reads_cpu_and_memory, "second_refresh_reads_cpu_and_memory")
			run_test (agent t.test_forced_layout_fault_is_refused, "forced_layout_fault_is_refused")
			run_test (agent t.test_system_clock_moves_forward, "system_clock_moves_forward")
		end

	run_slot_tests
		local
			t: TEST_SLOT
		do
			section ("frame slot and SCOOP consumer")
			create t
			run_test (agent t.test_put_then_clear, "put_then_clear")
			run_test (agent t.test_stopped_flag, "stopped_flag")
			run_test (agent t.test_unread_frame_counts_as_dropped, "unread_frame_counts_as_dropped")
			run_test (agent t.test_stop_request_keeps_the_frame, "stop_request_keeps_the_frame")
			run_test (agent t.test_empty_frame_refused, "empty_frame_refused")
			run_test (agent t.test_slot_on_its_own_processor, "slot_on_its_own_processor")
			run_test (agent t.test_worker_and_replayer_are_creatable_separately, "worker_and_replayer_are_creatable_separately")
			run_test (agent t.test_replay_feeds_the_slot, "replay_feeds_the_slot")
			run_test (agent t.test_replay_of_a_missing_file_reports_failure, "replay_of_a_missing_file_reports_failure")
		end

	run_lib_tests
		local
			t: LIB_TESTS
		do
			section ("facade")
			create t
			run_test (agent t.test_live_facade_opens_and_says_which_source, "live_facade_opens_and_says_which_source")
			run_test (agent t.test_capabilities_cover_every_metric, "capabilities_cover_every_metric")
			run_test (agent t.test_live_two_samples_make_a_frame_with_self, "live_two_samples_make_a_frame_with_self")
			run_test (agent t.test_interval_round_trip, "interval_round_trip")
			run_test (agent t.test_scripted_facade_makes_frames, "scripted_facade_makes_frames")
			run_test (agent t.test_injected_sources_have_no_self, "injected_sources_have_no_self")
			run_test (agent t.test_logger_records_decisions, "logger_records_decisions")
			run_test (agent t.test_close_closes_the_sources, "close_closes_the_sources")
		end

	run_coverage_model_tests
		local
			t: TEST_COVERAGE_MODEL
		do
			section ("phase 5 coverage: model")
			create t
			run_test (agent t.test_metric_accepts_its_exact_bounds, "metric_accepts_its_exact_bounds")
			run_test (agent t.test_registry_lookups, "registry_lookups")
			run_test (agent t.test_value_text_for_every_unit_kind, "value_text_for_every_unit_kind")
			run_test (agent t.test_one_decimal_rounds_half_away_from_zero, "one_decimal_rounds_half_away_from_zero")
			run_test (agent t.test_terabytes_cap_the_scale, "terabytes_cap_the_scale")
			run_test (agent t.test_sample_groups_and_values, "sample_groups_and_values")
			run_test (agent t.test_amount_of_each_resource, "amount_of_each_resource")
			run_test (agent t.test_decoded_newcomer_with_a_rate_is_invalid, "decoded_newcomer_with_a_rate_is_invalid")
			run_test (agent t.test_self_activity_and_counts, "self_activity_and_counts")
			run_test (agent t.test_top_by_asks_for_more_than_exist, "top_by_asks_for_more_than_exist")
			run_test (agent t.test_ring_wraps_many_times, "ring_wraps_many_times")
			run_test (agent t.test_zero_capacity_refused, "zero_capacity_refused")
			run_test (agent t.test_contains_span_and_empty_window, "contains_span_and_empty_window")
			run_test (agent t.test_aggregate_per_instance, "aggregate_per_instance")
			run_test (agent t.test_includes, "includes")
			run_test (agent t.test_capabilities_by_hand, "capabilities_by_hand")
			run_test (agent t.test_sampler_keeps_previous_snapshot, "sampler_keeps_previous_snapshot")
			run_test (agent t.test_budget_streaks_reset_on_change, "budget_streaks_reset_on_change")
		end

	run_coverage_probe_tests
		local
			t: TEST_COVERAGE_PROBE
		do
			section ("phase 5 coverage: probe")
			create t
			run_test (agent t.test_self_check_decides_once, "self_check_decides_once")
			run_test (agent t.test_kinds_and_nativeness, "kinds_and_nativeness")
			run_test (agent t.test_native_like_script_must_list_idle, "native_like_script_must_list_idle")
			run_test (agent t.test_duplicate_identities_break_the_read_contract, "duplicate_identities_break_the_read_contract")
			run_test (agent t.test_scripted_support_reasons_and_codes, "scripted_support_reasons_and_codes")
			run_test (agent t.test_win_source_explains_every_refusal, "win_source_explains_every_refusal")
			run_test (agent t.test_uncapped_counter, "uncapped_counter")
			run_test (agent t.test_topology_accessors_and_bounds, "topology_accessors_and_bounds")
			run_test (agent t.test_plain_names_and_folders, "plain_names_and_folders")
			run_test (agent t.test_capabilities_and_failure_texts, "capabilities_and_failure_texts")
		end

	run_codec_robustness_tests
		local
			t: TEST_CODEC_ROBUSTNESS
		do
			section ("phase 5 coverage: codec robustness")
			create t
			run_test (agent t.test_garbage_never_raises, "garbage_never_raises")
			run_test (agent t.test_wrong_field_count_names_its_line, "wrong_field_count_names_its_line")
			run_test (agent t.test_negative_field_refused, "negative_field_refused")
			run_test (agent t.test_repeated_identity_refused, "repeated_identity_refused")
			run_test (agent t.test_idle_activity_refused, "idle_activity_refused")
			run_test (agent t.test_unknown_metric_and_wrong_instance_refused, "unknown_metric_and_wrong_instance_refused")
			run_test (agent t.test_bad_escape_refused, "bad_escape_refused")
			run_test (agent t.test_discontinuity_with_processes_refused, "discontinuity_with_processes_refused")
			run_test (agent t.test_valid_lines_decode, "valid_lines_decode")
			run_test (agent t.test_capability_errors_are_separate, "capability_errors_are_separate")
		end

	run_worker_tests
		local
			t: TEST_WORKER
		do
			section ("phase 5 coverage: SCOOP handoff end to end")
			create t
			run_test (agent t.test_worker_samples_hands_over_and_stops, "worker_samples_hands_over_and_stops")
		end

	run_harden_scale_tests
		local
			t: TEST_HARDEN_SCALE
		do
			section ("phase 6 hardening: scale")
			create t
			run_test (agent t.test_five_thousand_processes, "five_thousand_processes")
			run_test (agent t.test_thousand_cores, "thousand_cores")
			run_test (agent t.test_an_hour_of_frames, "an_hour_of_frames")
			run_test (agent t.test_long_run_with_churn_and_clock_chaos, "long_run_with_churn_and_clock_chaos")
			run_test (agent t.test_hundred_thousand_series_writes, "hundred_thousand_series_writes")
		end

	run_harden_input_tests
		local
			t: TEST_HARDEN_INPUT
		do
			section ("phase 6 hardening: hostile input")
			create t
			run_test (agent t.test_hostile_names_round_trip, "hostile_names_round_trip")
			run_test (agent t.test_format_never_breaks_on_names, "format_never_breaks_on_names")
			run_test (agent t.test_every_prefix_of_a_frame_is_safe, "every_prefix_of_a_frame_is_safe")
			run_test (agent t.test_every_single_character_corruption_is_safe, "every_single_character_corruption_is_safe")
			run_test (agent t.test_impossible_bit_patterns_decode_invalid, "impossible_bit_patterns_decode_invalid")
			run_test (agent t.test_extreme_identities, "extreme_identities")
			run_test (agent t.test_negative_zero_and_tiny_values, "negative_zero_and_tiny_values")
			run_test (agent t.test_top_by_all_ties, "top_by_all_ties")
			run_test (agent t.test_slot_operations_in_any_order, "slot_operations_in_any_order")
			run_test (agent t.test_facade_closes_twice, "facade_closes_twice")
		end

	run_harden_scoop_tests
		local
			t: TEST_HARDEN_SCOOP
		do
			section ("phase 6 hardening: SCOOP and live repetition")
			create t
			run_test (agent t.test_two_readers_race_one_worker, "two_readers_race_one_worker")
			run_test (agent t.test_stop_requested_before_start, "stop_requested_before_start")
			run_test (agent t.test_workers_started_and_stopped_in_succession, "workers_started_and_stopped_in_succession")
			run_test (agent t.test_native_table_read_two_hundred_times, "native_table_read_two_hundred_times")
			run_test (agent t.test_documented_source_read_twenty_times, "documented_source_read_twenty_times")
			run_test (agent t.test_system_source_refreshed_fifty_times, "system_source_refreshed_fifty_times")
		end

	run_target_tests
		local
			t: TEST_TARGETS
		do
			section ("application targets: CLI commands and stress loads")
			create t
			run_test (agent t.test_capabilities_command_reports_every_metric, "capabilities_command_reports_every_metric")
			run_test (agent t.test_snapshot_command_describes_the_machine, "snapshot_command_describes_the_machine")
			run_test (agent t.test_snapshot_command_saves_frames_for_replay, "snapshot_command_saves_frames_for_replay")
			run_test (agent t.test_synthetic_command_writes_replayable_frames, "synthetic_command_writes_replayable_frames")
			run_test (agent t.test_clock_watch_sees_no_jump_when_awake, "clock_watch_sees_no_jump_when_awake")
			run_test (agent t.test_commands_refuse_bad_values, "commands_refuse_bad_values")
			run_test (agent t.test_spinner_on_its_own_processor, "spinner_on_its_own_processor")
			run_test (agent t.test_disk_load_round_trip, "disk_load_round_trip")
		end

	run_recorder_tests
		local
			t: TEST_RECORDER
		do
			section ("phase 2: recorder")
			create t
			run_test (agent t.test_policy_defaults, "policy_defaults")
			run_test (agent t.test_policy_significance, "policy_significance")
			run_test (agent t.test_policy_buckets, "policy_buckets")
			run_test (agent t.test_reduce_keeps_significant_only, "reduce_keeps_significant_only")
			run_test (agent t.test_reduce_skips_large_quiet_between_passes, "reduce_skips_large_quiet_between_passes")
			run_test (agent t.test_reduce_caps_and_counts_omitted, "reduce_caps_and_counts_omitted")
			run_test (agent t.test_reduce_picks_from_each_ranking, "reduce_picks_from_each_ranking")
			run_test (agent t.test_merge_weighted_mean, "merge_weighted_mean")
			run_test (agent t.test_merge_peak_takes_max, "merge_peak_takes_max")
			run_test (agent t.test_merge_never_available_keeps_reason, "merge_never_available_keeps_reason")
			run_test (agent t.test_merge_partly_available_uses_measured_time_only, "merge_partly_available_uses_measured_time_only")
			run_test (agent t.test_merge_process_rates_and_memory, "merge_process_rates_and_memory")
			run_test (agent t.test_merge_flags, "merge_flags")
			run_test (agent t.test_planner_groups_by_bucket, "planner_groups_by_bucket")
			run_test (agent t.test_planner_breaks_at_pin_and_gap, "planner_breaks_at_pin_and_gap")
			run_test (agent t.test_planner_ignores_young_frames, "planner_ignores_young_frames")
			run_test (agent t.test_memory_store_append_window_nearest, "memory_store_append_window_nearest")
			run_test (agent t.test_memory_store_retention_merges_old_frames, "memory_store_retention_merges_old_frames")
			run_test (agent t.test_memory_store_retention_runs_all_tiers, "memory_store_retention_runs_all_tiers")
			run_test (agent t.test_memory_store_pinned_frames_survive, "memory_store_pinned_frames_survive")
			run_test (agent t.test_sqlite_round_trip, "sqlite_round_trip")
			run_test (agent t.test_sqlite_keeps_non_ascii_names, "sqlite_keeps_non_ascii_names")
			run_test (agent t.test_sqlite_reader_sees_committed_frames_only, "sqlite_reader_sees_committed_frames_only")
			run_test (agent t.test_sqlite_writer_reopens_and_continues, "sqlite_writer_reopens_and_continues")
			run_test (agent t.test_sqlite_retention_matches_memory, "sqlite_retention_matches_memory")
			run_test (agent t.test_sqlite_size_cap_deletes_oldest, "sqlite_size_cap_deletes_oldest")
			run_test (agent t.test_sqlite_schema_refuses_a_fake_zero, "sqlite_schema_refuses_a_fake_zero")
			run_test (agent t.test_sqlite_reader_of_missing_file_says_why, "sqlite_reader_of_missing_file_says_why")
			run_test (agent t.test_facade_records_each_new_frame, "facade_records_each_new_frame")
			run_test (agent t.test_facade_skips_frames_out_of_order, "facade_skips_frames_out_of_order")
			run_test (agent t.test_trace_command_describes_a_recording, "trace_command_describes_a_recording")
			run_test (agent t.test_trace_command_without_a_recording_exits_3, "trace_command_without_a_recording_exits_3")
			run_test (agent t.test_single_writer_second_is_refused, "single_writer_second_is_refused")
			run_test (agent t.test_single_writer_release_lets_the_next_in, "single_writer_release_lets_the_next_in")
		end

	run_harden_recorder_tests
		local
			t: TEST_HARDEN_RECORDER
		do
			section ("phase 6 hardening: recorder")
			create t
			run_test (agent t.test_damaged_payload_is_skipped_with_a_reason, "damaged_payload_is_skipped_with_a_reason")
			run_test (agent t.test_newer_format_is_refused, "newer_format_is_refused")
			run_test (agent t.test_a_database_that_is_not_a_recording_is_refused, "a_database_that_is_not_a_recording_is_refused")
			run_test (agent t.test_a_text_file_is_refused, "a_text_file_is_refused")
			run_test (agent t.test_gap_frames_move_alone_in_both_stores, "gap_frames_move_alone_in_both_stores")
			run_test (agent t.test_pinned_frames_survive_the_size_cap, "pinned_frames_survive_the_size_cap")
			run_test (agent t.test_out_of_order_append_is_refused, "out_of_order_append_is_refused")
			run_test (agent t.test_bad_policies_are_refused, "bad_policies_are_refused")
			run_test (agent t.test_two_hours_of_frames_retain_in_time, "two_hours_of_frames_retain_in_time")
		end

	run_startup_tests
		local
			t: TEST_STARTUP
		do
			section ("phase 3: startup apps and the background recorder")
			create t
			run_test (agent t.test_impact_from_recorded_frames, "impact_from_recorded_frames")
			run_test (agent t.test_impact_without_recording_says_so, "impact_without_recording_says_so")
			run_test (agent t.test_list_reads_and_toggles_an_entry, "list_reads_and_toggles_an_entry")
			run_test (agent t.test_every_item_is_named, "every_item_is_named")
			run_test (agent t.test_recorder_registration_round_trip, "recorder_registration_round_trip")
		end

	run_services_tests
		local
			t: TEST_SERVICES
		do
			section ("phase 3: services")
			create t
			run_test (agent t.test_services_are_listed, "services_are_listed")
			run_test (agent t.test_start_types_are_remembered, "start_types_are_remembered")
			run_test (agent t.test_actions_on_a_missing_service_are_refused, "actions_on_a_missing_service_are_refused")
			run_test (agent t.test_descriptions_read, "descriptions_read")
		end

	run_settings_tests
		local
			t: TEST_SETTINGS
		do
			section ("phase 3: settings")
			create t
			run_test (agent t.test_settings_round_trip, "settings_round_trip")
			run_test (agent t.test_missing_file_keeps_defaults, "missing_file_keeps_defaults")
			run_test (agent t.test_bad_file_keeps_defaults, "bad_file_keeps_defaults")
		end

	run_performance_tests
		local
			t: TEST_PERFORMANCE
		do
			section ("phase 3: performance measurements")
			create t
			run_test (agent t.test_machine_facts, "machine_facts")
			run_test (agent t.test_new_counters_read_live, "new_counters_read_live")
			run_test (agent t.test_gpu_engines_or_reason, "gpu_engines_or_reason")
			run_test (agent t.test_counts_format_as_whole_numbers, "counts_format_as_whole_numbers")
		end

	run_control_tests
		local
			t: TEST_CONTROL
		do
			section ("phase 3: process details and actions")
			create t
			run_test (agent t.test_priority_classes, "priority_classes")
			run_test (agent t.test_action_results, "action_results")
			run_test (agent t.test_details_of_this_process, "details_of_this_process")
			run_test (agent t.test_a_reused_pid_reads_as_gone, "a_reused_pid_reads_as_gone")
			run_test (agent t.test_system_is_protected, "system_is_protected")
			run_test (agent t.test_window_index_finds_windows, "window_index_finds_windows")
			run_test (agent t.test_priority_and_efficiency_round_trip, "priority_and_efficiency_round_trip")
			run_test (agent t.test_end_task_needs_a_window, "end_task_needs_a_window")
			run_test (agent t.test_end_tree_ends_parent_and_child, "end_tree_ends_parent_and_child")
			run_test (agent t.test_actions_on_an_ended_process_are_refused, "actions_on_an_ended_process_are_refused")
		end

	run_acceptance_tests
			-- Facts about the reference machine; skipped, and said so, anywhere else.
		local
			t: TEST_ACCEPTANCE
			l_env: SIMPLE_ENV
		do
			section ("acceptance on " + Reference_machine)
			create l_env
			if attached l_env.item ("COMPUTERNAME") as al_name and then al_name.same_string_general (Reference_machine) then
				create t
				run_test (agent t.test_native_table_trusted_here, "native_table_trusted_here")
				run_test (agent t.test_native_read_lists_idle_and_self, "native_read_lists_idle_and_self")
				run_test (agent t.test_win_capabilities_here, "win_capabilities_here")
				run_test (agent t.test_documented_denies_rather_than_zeroes, "documented_denies_rather_than_zeroes")
				run_test (agent t.test_package_power_reads_a_plausible_value, "package_power_reads_a_plausible_value")
				run_test (agent t.test_live_facade_uses_the_native_table, "live_facade_uses_the_native_table")
			else
				say ("  SKIPPED: not the reference machine%N")
			end
		end

	Reference_machine: STRING = "JACKJACK"
			-- Where the Phase 1 acceptance facts were measured.

feature {NONE} -- Implementation

	passed: INTEGER
	failed: INTEGER

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run one test, counting the outcome. A failing assertion or a
			-- contract violation raises; the rescue reports it and goes on.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				say ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			say ("  FAIL: " + a_name + failure_detail + "%N")
			failed := failed + 1
			l_retried := True
			retry
		end

	failure_detail: STRING
			-- " (tag)" of the exception being rescued, when there is one.
		local
			l_factory: EXCEPTION_MANAGER_FACTORY
			l_utf: UTF_CONVERTER
		do
			create Result.make_empty
			create l_factory
			if attached l_factory.exception_manager.last_exception as al_exception then
				Result.append (" [")
				Result.append (al_exception.generator)
				if attached al_exception.description as al_text then
					Result.append (": ")
					Result.append (l_utf.string_32_to_utf_8_string_8 (al_text))
				end
				Result.append ("]")
			end
		end

	section (a_name: STRING)
			-- Print a section heading.
		do
			say ("%N-- " + a_name + " --%N")
		end

	say (a_text: STRING)
			-- Print `a_text' and flush, so a crash cannot swallow it.
		do
			io.put_string (a_text)
			io.output.flush
		end

end
