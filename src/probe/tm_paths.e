note
	description: "[
		Per-user folders under %LOCALAPPDATA%\simple_taskman: the trace file
		and one log file per target and processor (R-3). The trace stays in
		the owner's own profile (intent Q9). This class only computes paths;
		it creates no folder and opens no file.
	]"
	author: "Larry Rix"

class
	TM_PATHS

create
	make,
	make_with_base

feature {NONE} -- Initialization

	make
			-- Paths under this user's LOCALAPPDATA.
		local
			l_env: SIMPLE_ENV
		do
			create l_env
			if attached l_env.item ("LOCALAPPDATA") as al_base and then not al_base.is_empty then
				make_with_base (al_base)
			else
				create root.make_empty
				create missing_reason.make_from_string ({STRING_32} "LOCALAPPDATA is not set")
			end
		ensure
			rooted_or_said_why: has_root xor not missing_reason.is_empty
		end

	make_with_base (a_base: READABLE_STRING_32)
			-- Paths under `a_base' (tests use a scratch folder).
		require
			base_given: not a_base.is_empty
		do
			create root.make_from_string (a_base)
			if not root.ends_with ({STRING_32} "\") then
				root.append ({STRING_32} "\")
			end
			root.append ({STRING_32} "simple_taskman")
			create missing_reason.make_empty
		ensure
			rooted: has_root
			under_base: root.starts_with (a_base)
		end

feature -- Access

	root: STRING_32
			-- %LOCALAPPDATA%\simple_taskman, or empty.

	missing_reason: STRING_32
			-- Why there is no root; empty when there is one.

	trace_path: STRING_32
			-- The one trace file per user.
		require
			rooted: has_root
		do
			Result := root + {STRING_32} "\trace.db"
		ensure
			under_root: Result.starts_with (root)
		end

	logs_folder: STRING_32
			-- Folder of the log files.
		require
			rooted: has_root
		do
			Result := root + {STRING_32} "\logs"
		ensure
			under_root: Result.starts_with (root)
		end

	log_path (a_target, a_processor: READABLE_STRING_32): STRING_32
			-- logs\<target>-<processor>.log; one file per processor, because the
			-- logger reopens its file per message and two writers would interleave.
		require
			rooted: has_root
			target_given: not a_target.is_empty
			processor_given: not a_processor.is_empty
			plain_names: is_plain_name (a_target) and is_plain_name (a_processor)
		do
			Result := logs_folder + {STRING_32} "\" + a_target + {STRING_32} "-" + a_processor + {STRING_32} ".log"
		ensure
			in_logs: Result.starts_with (logs_folder)
			is_log: Result.ends_with ({STRING_32} ".log")
		end

feature -- Status report

	has_root: BOOLEAN
			-- Is there a per-user folder?
		do
			Result := not root.is_empty
		end

	is_plain_name (a_name: READABLE_STRING_32): BOOLEAN
			-- ASCII letters and digits, '_' and '-' only: safe and portable inside a file name.
		do
			Result := not a_name.is_empty and then
				across a_name as ic all
					(ic.code < 128 and then ic.is_alpha_numeric) or ic = {CHARACTER_32} '_' or ic = {CHARACTER_32} '-'
				end
		end

invariant
	rooted_or_said_why: has_root xor not missing_reason.is_empty

end
