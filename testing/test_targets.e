note
	description: "[
		The application targets' logic, driven directly: the CLI command
		classes (which build text and an exit code, never print) and the
		stress loads. Live on this machine, machine-neutral in what they assert.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_TARGETS

inherit
	TM_TEST_SET

feature -- Tests: CLI commands

	test_capabilities_command_reports_every_metric
		note
			testing: "covers/{TM_CAPABILITIES_COMMAND}.execute"
		local
			l_command: TM_CAPABILITIES_COMMAND
		do
			create l_command.make
			l_command.execute
			assert_integers_equal ("exit 0", 0, l_command.exit_code)
			assert_string_contains ("process table line", l_command.output, "process_table")
			assert_string_contains ("a metric line", l_command.output, "cpu.busy_pct")
		end

	test_snapshot_command_describes_the_machine
		note
			testing: "covers/{TM_SNAPSHOT_COMMAND}.execute"
		local
			l_command: TM_SNAPSHOT_COMMAND
		do
			create l_command.make (5, 250, True)
			l_command.execute
			assert_integers_equal ("exit 0", 0, l_command.exit_code)
			assert_string_contains ("table header", l_command.output, "PID")
			assert_string_contains ("own cost", l_command.output, "this tool:")
			assert_string_not_contains ("never a bare zero watt reading", l_command.output, "package_watts       0.0 W")
		end

	test_snapshot_command_saves_frames_for_replay
		note
			testing: "covers/{TM_SNAPSHOT_COMMAND}.set_save"
		local
			l_command: TM_SNAPSHOT_COMMAND
			l_path: STRING_32
			l_codec: TM_FRAME_CODEC
			l_texts: ARRAYED_LIST [STRING_8]
		do
			l_path := scratch_path ({STRING_32} "taskman_saved_frames.tmf")
			create l_command.make (1, 250, False)
			l_command.set_save (2, l_path)
			l_command.execute
			assert_integers_equal ("two saved", 2, l_command.frames_saved)
			create l_codec.make
			l_texts := l_codec.frame_texts_in (file_text (l_path))
			assert_integers_equal ("two in the file", 2, l_texts.count)
			l_codec.decode (l_texts [2])
			assert_true ({STRING_32} "decodes: " + l_codec.last_error, l_codec.has_frame)
			delete_file (l_path)
		end

	test_synthetic_command_writes_replayable_frames
		note
			testing: "covers/{TM_SYNTHETIC_COMMAND}.execute"
		local
			l_command: TM_SYNTHETIC_COMMAND
			l_path: STRING_32
			l_codec: TM_FRAME_CODEC
			l_texts: ARRAYED_LIST [STRING_8]
		do
			l_path := scratch_path ({STRING_32} "taskman_synthetic_test.tmf")
			create l_command.make (60, 3, l_path)
			l_command.execute
			assert_integers_equal ("three written", 3, l_command.frames_written)
			create l_codec.make
			l_texts := l_codec.frame_texts_in (file_text (l_path))
			assert_integers_equal ("three in the file", 3, l_texts.count)
			l_codec.decode (l_texts [3])
			assert_true ({STRING_32} "decodes: " + l_codec.last_error, l_codec.has_frame)
			assert_true ("sixty processes (some churned in)", l_codec.last_frame.activity_count = 60)
			assert_integers_equal ("32 scripted cores", 32,
				l_codec.last_frame.readings.instances ({TM_METRICS}.Cpu_core_busy_pct).count)
			delete_file (l_path)
		end

	test_clock_watch_sees_no_jump_when_awake
		note
			testing: "covers/{TM_CLOCK_WATCH_COMMAND}.execute"
		local
			l_command: TM_CLOCK_WATCH_COMMAND
		do
			create l_command.make (2)
			l_command.execute
			assert_integers_equal ("no jump", 0, l_command.jumps)
			assert_string_contains ("summary", l_command.output, "watched 2 s")
		end

	test_commands_refuse_bad_values
		note
			testing: "covers/{TM_SNAPSHOT_COMMAND}.make"
		do
			assert_true ("top 0", raises (agent new_snapshot (0, 1000)))
			assert_true ("interval 100", raises (agent new_snapshot (5, 100)))
			assert_true ("no processes", raises (agent new_synthetic (0)))
			assert_true ("disk load of 0 MB", raises (agent new_disk_load (0)))
		end

feature -- Tests: stress loads

	test_spinner_on_its_own_processor
		note
			testing: "covers/{TM_SPINNER}.spin"
		local
			l_spinner: separate TM_SPINNER
		do
			create l_spinner.make
			spin (l_spinner, 200)
			assert_true ("worked", iterations (l_spinner) > 0)
			assert_true ("done", done (l_spinner))
		end

	test_disk_load_round_trip
		note
			testing: "covers/{TM_DISK_LOAD}.run"
		local
			l_load: TM_DISK_LOAD
			l_file: PLAIN_TEXT_FILE
		do
			create l_load.make (scratch_path ({STRING_32} ""), 4)
			l_load.run (1)
			assert_string_empty ({STRING_32} "no error: " + l_load.last_error, l_load.last_error)
			assert_true ("at least one pass", l_load.passes > 0)
			assert_true ("read what it wrote", l_load.bytes_read = l_load.bytes_written)
			create l_file.make_with_name (l_load.path)
			assert_false ("scratch file deleted", l_file.exists)
		end

feature {NONE} -- Fixtures

	new_snapshot (a_top, a_interval: INTEGER)
		local
			l_command: TM_SNAPSHOT_COMMAND
		do
			create l_command.make (a_top, a_interval, False)
		end

	new_synthetic (a_processes: INTEGER)
		local
			l_command: TM_SYNTHETIC_COMMAND
		do
			create l_command.make (a_processes, 1, {STRING_32} "x.tmf")
		end

	new_disk_load (a_mb: INTEGER)
		local
			l_load: TM_DISK_LOAD
		do
			create l_load.make ({STRING_32} "C:\x", a_mb)
		end

	spin (a_spinner: separate TM_SPINNER; a_ms: INTEGER)
		do
			a_spinner.spin (a_ms)
		end

	iterations (a_spinner: separate TM_SPINNER): INTEGER_64
			-- Waits for the spin to finish (the spinner's processor is busy until then).
		do
			Result := a_spinner.iterations
		end

	done (a_spinner: separate TM_SPINNER): BOOLEAN
		do
			Result := a_spinner.is_done
		end

end
