note
	description: "[
		taskman_recorder.exe: records with no window (intent v2 R-5, Phase 2
		SHOULD). Started at logon when the owner turns on "Record from logon",
		or by the window. It holds Local\simple_taskman.recorder.alive while it
		runs and waits on Local\simple_taskman.recorder.stop. When a window
		already holds the one-writer lock it waits and tries again every 30 s,
		so recording carries on after the window closes. Every decision goes
		to logs\taskman-recorder.log (oracle rule: an unattended loop logs its
		decisions). Never prints: it is a GUI-subsystem program with no window.
	]"
	author: "Larry Rix"

class
	TM_RECORDER_APP

inherit
	EXCEPTION_MANAGER_FACTORY
		export
			{NONE} all
		end

create
	make

feature {NONE} -- Initialization

	make
			-- Record until asked to stop.
		local
			l_paths: TM_PATHS
			l_folder: DIRECTORY
			l_waiting_logged: BOOLEAN
		do
			create l_paths.make
			if l_paths.has_root then
				create l_folder.make_with_name (l_paths.logs_folder)
				if not l_folder.exists then
					l_folder.recursive_create_dir
				end
				create logger.make_to_file ((create {UTF_CONVERTER}).string_32_to_utf_8_string_8 (l_paths.log_path ({STRING_32} "taskman", {STRING_32} "recorder")))
				alive := c_create_alive
				stop_event := c_create_stop_event
				log ({STRING_32} "recorder started")
				from
				until
					stop_requested (0)
				loop
					if record_once (l_paths.trace_path) then
						l_waiting_logged := False
					else
						if not l_waiting_logged then
							log ({STRING_32} "another simple_taskman records; waiting (retry every 30 s)")
							l_waiting_logged := True
						end
						stop_requested (30_000).do_nothing
					end
				end
				log ({STRING_32} "recorder stopped on request")
			end
		end

feature {NONE} -- Recording

	record_once (a_trace: STRING_32): BOOLEAN
			-- Take the lock and record until asked to stop; False when another writer holds the lock.
		local
			l_lock: TM_SINGLE_WRITER
			l_store: TM_SQLITE_TRACE_STORE
			l_tm: SIMPLE_TASKMAN
			l_clock: TM_SYSTEM_CLOCK
			l_failures: INTEGER
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_lock.make ({TM_SINGLE_WRITER}.Default_name)
				if l_lock.is_owner then
					Result := True
					create l_store.make_writer (a_trace, create {TM_RETENTION_POLICY}.make_default)
					if l_store.is_writable then
						log ({STRING_32} "recording to " + a_trace)
						create l_tm.make
						l_tm.set_nominal_interval (1000).do_nothing
						if attached logger as al_logger then
							l_tm.set_logger (al_logger).do_nothing
						end
						l_tm.attach_store (l_store).do_nothing
						create l_clock.make
						from
						until
							stop_requested (0) or l_failures >= 3
						loop
							l_tm.sample
							if stop_requested (((10_000_000 - l_tm.last_tick_cost) // 10_000).to_integer_32.max (50)) then
								-- leave the loop
							end
						end
						l_tm.close
						log ({STRING_32} "recorded " + l_tm.recorded.out.to_string_32 + {STRING_32} " frames this run")
					else
						log ({STRING_32} "cannot record: " + l_store.last_error)
						stop_requested (30_000).do_nothing
					end
					l_lock.release
				end
			end
		rescue
			log ({STRING_32} "recording failed: " + exception_text)
			l_retried := True
			Result := True
			retry
		end

	stop_requested (a_wait_ms: INTEGER): BOOLEAN
			-- Wait up to `a_wait_ms' for the stop event; was it set?
		do
			Result := c_wait (stop_event, a_wait_ms)
		end

	log (a_line: READABLE_STRING_32)
		do
			if attached logger as al_logger then
				al_logger.info (a_line)
			end
		end

	exception_text: STRING_32
		do
			if attached exception_manager.last_exception as al_exception and then attached al_exception.description as al_text then
				create Result.make_from_string_general (al_text)
			else
				create Result.make_from_string ({STRING_32} "unknown exception")
			end
		end

	logger: detachable SIMPLE_LOGGER
	alive: POINTER
	stop_event: POINTER

feature {NONE} -- Externals

	c_create_alive: POINTER
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_POINTER) CreateMutexW (NULL, FALSE, L%"Local\\simple_taskman.recorder.alive%");"
		end

	c_create_stop_event: POINTER
			-- Manual-reset stop event, cleared at start.
		external
			"C inline use <windows.h>"
		alias
			"[
				HANDLE l_event = CreateEventW (NULL, TRUE, FALSE, L"Local\\simple_taskman.recorder.stop");
				if (l_event != NULL) ResetEvent (l_event);
				return (EIF_POINTER) l_event;
			]"
		end

	c_wait (a_event: POINTER; a_ms: INTEGER): BOOLEAN
		external
			"C inline use <windows.h>"
		alias
			"[
				if ($a_event == NULL) { if ($a_ms > 0) Sleep ((DWORD) $a_ms); return EIF_FALSE; }
				return (EIF_BOOLEAN) (WaitForSingleObject ((HANDLE) $a_event, (DWORD) $a_ms) == WAIT_OBJECT_0);
			]"
		end

end
