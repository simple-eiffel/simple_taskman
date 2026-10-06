note
	description: "[
		Trace store in one SQLite file (spec 04 "Recorder Design", schema
		version 1). A writer keeps a transaction open and commits every
		`Commit_every' frames, on `flush', after retention, and on `close'
		(batched commits, NFR-004); its own queries see the frames not yet
		committed. Other processes open the file with `make_reader' and see
		committed frames (WAL mode). The CHECK pairs in the schema keep a fake
		zero out of the file, whoever writes it (DR-001). The payload is the
		frame's TMF1 text compressed with zlib (meta payload_encoding = zlib):
		measured 2026-10-06, 4.5 KB of text became 1.5 KB.

		The processes table holds rows for tier 1 and 2 frames only, so
		per-process SQL covers everything older than an hour, while the
		1-second frames keep their processes in the payload alone. Measured
		2026-10-06 on JACKJACK: with rows for every frame and a commit every
		10 frames the recorder wrote 50 MB an hour, two and a half times the
		NFR-004 budget; most of it was index pages rewritten at each commit.

		Retention works on the store's own timeline (`latest_ticks', which
		only grows), so frames of a coarser tier never sit among the
		candidates of a finer one; each tier step loads only the candidate
		entries and pinned ones. The size cap deletes the oldest unpinned
		frames, never the newest, then reclaims pages (incremental vacuum).
	]"
	author: "Larry Rix"

class
	TM_SQLITE_TRACE_STORE

inherit
	TM_TRACE_STORE

create
	make_writer,
	make_reader

feature {NONE} -- Initialization

	make_writer (a_path: READABLE_STRING_32; a_policy: TM_RETENTION_POLICY)
			-- Open or create the recording at `a_path' for appending, governed by `a_policy'.
		require
			path_given: not a_path.is_empty
		local
			l_new: BOOLEAN
		do
			create path.make_from_string (a_path)
			policy := a_policy
			create last_error.make_empty
			create codec.make
			create compressor.make
			create merger.make (a_policy)
			create planner.make (a_policy)
			ensure_folder
			if last_error.is_empty then
				l_new := not file_exists
				open_database (False)
			end
			if is_open then
				prepare_schema (l_new, True)
				if last_error.is_empty then
					load_span
				end
				if last_error.is_empty then
					is_writable := True
				else
					release_database
				end
			end
		ensure
			path_kept: path.same_string (a_path)
			policy_kept: policy = a_policy
			writable_or_said_why: is_writable xor not last_error.is_empty
		end

	make_reader (a_path: READABLE_STRING_32)
			-- Open the existing recording at `a_path' read-only.
		require
			path_given: not a_path.is_empty
		do
			create path.make_from_string (a_path)
			create policy.make_default
			create last_error.make_empty
			create codec.make
			create compressor.make
			create merger.make (policy)
			create planner.make (policy)
			if not file_exists then
				fail ({STRING_32} "no recording at " + path)
			else
				open_database (True)
				if is_open then
					prepare_schema (False, False)
					if not last_error.is_empty then
							-- A read-only connection cannot create the WAL index of a
							-- closed recording; a connection that never writes can.
						release_database
						last_error.wipe_out
						open_database (False)
						if is_open then
							prepare_schema (False, False)
						end
					end
				end
				if is_open and last_error.is_empty then
					load_span
				end
				if is_open and not last_error.is_empty then
					release_database
				end
			end
		ensure
			path_kept: path.same_string (a_path)
			read_only: not is_writable
			open_or_said_why: is_open xor not last_error.is_empty
		end

feature -- Access

	path: STRING_32
			-- The recording file.

	window (a_from, a_to: INTEGER_64): TM_WINDOW
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			create Result.make
			l_rows := rows ("SELECT payload FROM frames WHERE start_ticks >= " + a_from.out + " AND end_ticks <= "
				+ a_to.out + " ORDER BY start_ticks")
			across l_rows.rows as ic loop
				if attached decoded (payload_of (ic)) as al_frame then
					if Result.is_empty or else al_frame.start_ticks >= Result.end_ticks then
						Result.extend (al_frame)
					end
				end
			end
		end

	frame_nearest (a_ticks: INTEGER_64): detachable TM_FRAME
		local
			l_before, l_after: SIMPLE_SQL_RESULT
			l_use_after: BOOLEAN
		do
			if frame_count > 0 then
				l_before := rows ("SELECT start_ticks, end_ticks, payload FROM frames WHERE start_ticks <= " + a_ticks.out
					+ " ORDER BY start_ticks DESC LIMIT 1")
				l_after := rows ("SELECT start_ticks, end_ticks, payload FROM frames WHERE start_ticks > " + a_ticks.out
					+ " ORDER BY start_ticks ASC LIMIT 1")
				if l_before.is_empty then
					l_use_after := True
				elseif l_after.is_empty or else l_before.first.integer_64_value ("end_ticks") > a_ticks then
					l_use_after := False
				else
					l_use_after := (l_after.first.integer_64_value ("start_ticks") - a_ticks)
						< (a_ticks - l_before.first.integer_64_value ("end_ticks"))
				end
				if l_use_after and not l_after.is_empty then
					Result := decoded (payload_of (l_after.first))
				elseif not l_before.is_empty then
					Result := decoded (payload_of (l_before.first))
				end
				if Result = Void and last_error.is_empty then
					last_error.append ({STRING_32} "no frame could be read near " + a_ticks.out)
				end
			end
		end

	entries: ARRAYED_LIST [TM_TRACE_ENTRY]
		do
			Result := entries_where ("1 = 1")
		end

	size_bytes: INTEGER_64
			-- Bytes the file holds in used pages (page count less free pages, times page size).
		require
			open: is_open
		do
			Result := ((pragma_value ("page_count") - pragma_value ("freelist_count")) * pragma_value ("page_size")).max (0)
		ensure
			non_negative: Result >= 0
		end

	process_row_count: INTEGER
			-- Rows in the processes table, for the size and write measurements.
		require
			open: is_open
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := rows ("SELECT COUNT(*) AS n FROM processes")
			if not l_rows.is_empty then
				Result := l_rows.first.integer_value ("n").max (0)
			end
		ensure
			non_negative: Result >= 0
		end

	Schema_version: INTEGER = 1

	Commit_every: INTEGER = 30
			-- Frames appended between automatic commits (a reader lags at most this many frames).

feature -- Element change

	refresh
			-- Re-read the count and span from the file, for a reader following a recording another process writes.
		require
			open: is_open
		do
			last_error.wipe_out
			load_span
		ensure
			span_ordered: frame_count > 0 implies latest_ticks > earliest_ticks
		end

	append (a_frame: TM_FRAME)
		do
			last_error.wipe_out
			begin_if_needed
			insert_frame (a_frame, 0)
			if last_error.is_empty then
				if frame_count = 0 then
					earliest_ticks := a_frame.start_ticks
				end
				latest_ticks := a_frame.end_ticks
				frame_count := frame_count + 1
				appended := appended + 1
				pending := pending + 1
				if pending = Commit_every then
					commit_now
				end
			end
		end

	flush
		do
			last_error.wipe_out
			commit_now
		end

	apply_retention
		local
			l_now, l_cutoff: INTEGER_64
			l_tier: INTEGER
			l_entries: ARRAYED_LIST [TM_TRACE_ENTRY]
		do
			last_error.wipe_out
			if frame_count > 0 then
				begin_if_needed
				l_now := latest_ticks
				from l_tier := 0 until l_tier = policy.Tier_count - 1 or not last_error.is_empty loop
					l_cutoff := l_now - policy.age_limit_ticks (l_tier)
					l_entries := entries_where ("end_ticks <= " + l_cutoff.out + " AND (tier = " + l_tier.out + " OR pinned = 1)")
					across planner.groups (l_entries, l_tier, l_cutoff) as g until not last_error.is_empty loop
						apply_group (g)
					end
					l_tier := l_tier + 1
				end
				exec ("DELETE FROM frames WHERE tier = " + (policy.Tier_count - 1).out + " AND pinned = 0 AND end_ticks <= "
					+ (l_now - policy.age_limit_ticks (policy.Tier_count - 1)).out + " AND end_ticks < " + l_now.out)
				enforce_cap
				commit_now
				if cap_deletions > 0 then
						-- Only the cap shrinks the file. Pages freed by merging are reused by the next
						-- appends; vacuuming them each pass rewrote pages for nothing (measured 2026-10-06:
						-- 27.5 MB/h written once merging began, against 6 MB/h before).
					exec ("PRAGMA incremental_vacuum")
				end
				load_span
			end
		end

	pin (a_from, a_to: INTEGER_64)
		do
			last_error.wipe_out
			begin_if_needed
			exec ("UPDATE frames SET pinned = 1 WHERE start_ticks < " + a_to.out + " AND end_ticks > " + a_from.out)
		end

	close
		do
			if is_writable then
				commit_now
			end
			release_database
		end

feature -- Status report

	pending: INTEGER
			-- Frames appended since the last commit.

feature {NONE} -- Database

	database: detachable SIMPLE_SQL_DATABASE
			-- The connection while open.

	codec: TM_FRAME_CODEC
	compressor: SIMPLE_COMPRESSION
	merger: TM_FRAME_MERGER
	planner: TM_RETENTION_PLANNER

	db: SIMPLE_SQL_DATABASE
			-- The open connection.
		require
			open: is_open
		do
			if attached database as al_db then
				Result := al_db
			else
					-- Not reached while open.
				create Result.make_memory
			end
		end

	open_database (a_read_only: BOOLEAN)
			-- Connect to `path'; on failure say why and stay closed.
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				if a_read_only then
					create database.make_read_only (path)
				else
					create database.make (path)
				end
				is_open := attached database as al_db and then al_db.is_open
				if not is_open then
					fail ({STRING_32} "could not open " + path)
				end
			end
		rescue
			l_failed := True
			database := Void
			is_open := False
			fail ({STRING_32} "could not open " + path)
			retry
		end

	release_database
			-- Disconnect; a failure while closing is not raised (the connection is dropped either way).
		local
			l_failed: BOOLEAN
		do
			if not l_failed and then attached database as al_db then
				al_db.close
			end
			database := Void
			is_open := False
			is_writable := False
			pending := 0
		ensure
			closed: not is_open and not is_writable and pending = 0
		rescue
			l_failed := True
			retry
		end

	prepare_schema (a_new, a_writer: BOOLEAN)
			-- Set the pragmas, create the schema in a new file, and check its version.
		require
			open: is_open
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			if a_writer then
				if a_new then
					exec ("PRAGMA auto_vacuum = INCREMENTAL")
				end
				l_rows := rows ("PRAGMA journal_mode = WAL")
				exec ("PRAGMA synchronous = NORMAL")
				exec ("PRAGMA foreign_keys = ON")
				if last_error.is_empty and then rows ("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'meta'").is_empty then
					create_schema
				end
			end
			if last_error.is_empty then
				l_rows := rows ("SELECT value FROM meta WHERE key = 'schema_version'")
				if not last_error.is_empty or else l_rows.is_empty then
					last_error.wipe_out
					fail (path + {STRING_32} " is not a simple_taskman recording")
				elseif not l_rows.first.string_value ("value").same_string (Schema_version.out) then
					fail (path + {STRING_32} " has recording format " + l_rows.first.string_value ("value")
						+ {STRING_32} "; this build reads format " + Schema_version.out)
				end
			end
		end

	create_schema
			-- Tables, indexes, and meta rows of schema version 1 (spec 04).
		do
			exec ("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
			exec ("[
				CREATE TABLE frames (
				   id INTEGER PRIMARY KEY,
				   start_ticks INTEGER NOT NULL, end_ticks INTEGER NOT NULL,
				   duration_ticks INTEGER NOT NULL CHECK (duration_ticks > 0),
				   tier INTEGER NOT NULL CHECK (tier IN (0, 1, 2)),
				   discontinuity INTEGER NOT NULL CHECK (discontinuity IN (0, 1)),
				   pinned INTEGER NOT NULL DEFAULT 0,
				   process_count INTEGER NOT NULL, omitted_processes INTEGER NOT NULL,
				   cpu_busy_pct REAL, cpu_busy_status INTEGER NOT NULL,
				   mem_commit_pct REAL, mem_commit_status INTEGER NOT NULL,
				   disk_busy_max_pct REAL, disk_busy_status INTEGER NOT NULL,
				   package_watts REAL, package_watts_status INTEGER NOT NULL,
				   lag_max_ms REAL, lag_status INTEGER NOT NULL,
				   payload BLOB NOT NULL,
				   CHECK ((cpu_busy_status = 0) = (cpu_busy_pct IS NOT NULL)),
				   CHECK ((mem_commit_status = 0) = (mem_commit_pct IS NOT NULL)),
				   CHECK ((disk_busy_status = 0) = (disk_busy_max_pct IS NOT NULL)),
				   CHECK ((package_watts_status = 0) = (package_watts IS NOT NULL)),
				   CHECK ((lag_status = 0) = (lag_max_ms IS NOT NULL)))
			]")
			exec ("CREATE INDEX frames_by_end ON frames (tier, end_ticks)")
			exec ("CREATE INDEX frames_by_start ON frames (start_ticks)")
			exec ("[
				CREATE TABLE processes (
				   frame_id INTEGER NOT NULL REFERENCES frames (id) ON DELETE CASCADE,
				   pid INTEGER NOT NULL, creation_ticks INTEGER NOT NULL, name TEXT NOT NULL,
				   cpu_cores REAL, cpu_status INTEGER NOT NULL,
				   io_read_bps REAL, io_write_bps REAL, io_status INTEGER NOT NULL,
				   private_bytes INTEGER, working_set INTEGER, memory_status INTEGER NOT NULL,
				   PRIMARY KEY (frame_id, pid, creation_ticks))
			]")
			exec ("CREATE INDEX processes_by_identity ON processes (pid, creation_ticks)")
			exec ("INSERT INTO meta (key, value) VALUES ('schema_version', '" + Schema_version.out + "')")
			exec ("INSERT INTO meta (key, value) VALUES ('codec_version', 'TMF1')")
			exec ("INSERT INTO meta (key, value) VALUES ('payload_encoding', 'zlib')")
		end

	load_span
			-- Count and span from the file.
		require
			open: is_open
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := rows ("SELECT COUNT(*) AS n, MIN(start_ticks) AS s, MAX(end_ticks) AS e FROM frames")
			if l_rows.is_empty or else l_rows.first.integer_value ("n") <= 0 then
				frame_count := 0
				earliest_ticks := 0
				latest_ticks := 0
			else
				frame_count := l_rows.first.integer_value ("n")
				earliest_ticks := l_rows.first.integer_64_value ("s")
				latest_ticks := l_rows.first.integer_64_value ("e")
			end
		end

	begin_if_needed
			-- Open the batch transaction when none is open.
		require
			writable: is_writable
		local
			l_failed: BOOLEAN
		do
			if not l_failed and then not db.is_in_transaction then
				db.begin_transaction
				note_error ("BEGIN")
			end
		rescue
			l_failed := True
			note_exception ("BEGIN")
			retry
		end

	commit_now
			-- Commit the batch, if one is open.
		require
			writable: is_writable
		local
			l_failed: BOOLEAN
		do
			if not l_failed and then db.is_in_transaction then
				db.commit
				note_error ("COMMIT")
			end
			pending := 0
		ensure
			nothing_pending: pending = 0
		rescue
			l_failed := True
			note_exception ("COMMIT")
			retry
		end

	exec (a_sql: READABLE_STRING_8)
			-- Run `a_sql' unless an earlier step of this operation failed. simple_sql re-raises
			-- SQL failures (no such table, not a database); here they become `last_error'.
		require
			open: is_open
		local
			l_failed: BOOLEAN
		do
			if not l_failed and then last_error.is_empty then
				db.perform (a_sql)
				note_error (a_sql)
			end
		rescue
			l_failed := True
			note_exception (a_sql)
			retry
		end

	rows (a_sql: READABLE_STRING_8): SIMPLE_SQL_RESULT
			-- Rows of query `a_sql'; empty, with `last_error' set, when it fails.
		require
			open: is_open
		local
			l_failed: BOOLEAN
		do
			if l_failed then
				create Result.make_empty
			else
				Result := db.run_query (a_sql)
				note_error (a_sql)
			end
		rescue
			l_failed := True
			note_exception (a_sql)
			retry
		end

	note_exception (a_sql: READABLE_STRING_8)
			-- Record the exception being rescued while running `a_sql'.
		do
			if last_error.is_empty then
				last_error.append ({STRING_32} "SQLite: ")
				if attached (create {EXCEPTION_MANAGER_FACTORY}).exception_manager.last_exception as al_exception
						and then attached al_exception.description as al_text then
					last_error.append (al_text.to_string_32)
				else
					last_error.append ({STRING_32} "failed")
				end
				last_error.append ({STRING_32} " [" + a_sql.substring (1, a_sql.count.min (60)).to_string_32 + {STRING_32} "]")
			end
		ensure
			said_why: not last_error.is_empty
		end

	pragma_value (a_name: READABLE_STRING_8): INTEGER_64
			-- Integer value of PRAGMA `a_name'.
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := rows ("PRAGMA " + a_name)
			if not l_rows.is_empty and then l_rows.first.count > 0 then
				if attached {INTEGER_64} l_rows.first.values.first as al_value then
					Result := al_value
				end
			end
		end

	note_error (a_sql: READABLE_STRING_8)
			-- Record the connection's error from running `a_sql', if any.
		do
			if db.has_error and last_error.is_empty then
				last_error.append ({STRING_32} "SQLite: ")
				if attached db.last_error_message as al_message then
					last_error.append (al_message)
				end
				last_error.append ({STRING_32} " [" + a_sql.substring (1, a_sql.count.min (60)).to_string_32 + {STRING_32} "]")
			end
		end

	fail (a_reason: READABLE_STRING_32)
			-- Record `a_reason' unless a reason is already recorded.
		do
			if last_error.is_empty then
				last_error.append (a_reason)
			end
		ensure
			said_why: not last_error.is_empty
		end

feature {NONE} -- Files

	file_exists: BOOLEAN
			-- Does `path' exist?
		do
			Result := (create {RAW_FILE}.make_with_name (path)).exists
		end

	ensure_folder
			-- Create the folder that holds `path' when it is missing.
		local
			l_folder: DIRECTORY
			l_cut: INTEGER
			l_failed: BOOLEAN
		do
			if not l_failed then
				l_cut := path.last_index_of ({CHARACTER_32} '\', path.count)
				if l_cut > 1 then
					create l_folder.make_with_name (path.head (l_cut - 1))
					if not l_folder.exists then
						l_folder.recursive_create_dir
					end
				end
			end
		rescue
			l_failed := True
			fail ({STRING_32} "could not create the folder of " + path)
			retry
		end

feature {NONE} -- Frames

	insert_frame (a_frame: TM_FRAME; a_tier: INTEGER)
			-- Write `a_frame' in tier `a_tier' with its process rows.
		require
			writable: is_writable
			valid_tier: policy.is_valid_tier (a_tier)
		local
			l_sql: STRING_8
			l_id: INTEGER_64
		do
			create l_sql.make (4096)
			l_sql.append ("INSERT INTO frames (start_ticks, end_ticks, duration_ticks, tier, discontinuity, pinned, process_count, omitted_processes, cpu_busy_pct, cpu_busy_status, mem_commit_pct, mem_commit_status, disk_busy_max_pct, disk_busy_status, package_watts, package_watts_status, lag_max_ms, lag_status, payload) VALUES (")
			l_sql.append (a_frame.start_ticks.out + ", " + a_frame.end_ticks.out + ", " + a_frame.duration.out + ", ")
			l_sql.append (a_tier.out + ", " + a_frame.is_discontinuity.to_integer.out + ", 0, ")
			l_sql.append (a_frame.activity_count.out + ", " + a_frame.omitted_processes.out + ", ")
			append_headline (l_sql, a_frame.readings.reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} ""))
			append_headline (l_sql, a_frame.readings.reading ({TM_METRICS}.Mem_commit_pct, {STRING_32} ""))
			append_headline (l_sql, busiest_disk (a_frame.readings))
			append_headline (l_sql, a_frame.readings.reading ({TM_METRICS}.Cpu_package_watts, {STRING_32} ""))
			append_headline (l_sql, a_frame.readings.reading ({TM_METRICS}.Lag_max_ms, {STRING_32} ""))
			l_sql.append (hex_literal (compressor.compress_string (codec.encode (a_frame))))
			l_sql.append (")")
			exec (l_sql)
			if last_error.is_empty and a_tier >= 1 then
				l_id := db.last_insert_rowid
				across a_frame.activities as ic until not last_error.is_empty loop
					exec (process_row (l_id, ic))
				end
			end
		end

	process_row (a_frame_id: INTEGER_64; a_activity: TM_PROCESS_ACTIVITY): STRING_8
			-- INSERT for one process row.
		local
			l_utf: UTF_CONVERTER
		do
			create Result.make (256)
			Result.append ("INSERT INTO processes (frame_id, pid, creation_ticks, name, cpu_cores, cpu_status, io_read_bps, io_write_bps, io_status, private_bytes, working_set, memory_status) VALUES (")
			Result.append (a_frame_id.out + ", " + a_activity.id.pid.out + ", " + a_activity.id.creation_ticks.out + ", ")
			Result.append (quoted (l_utf.string_32_to_utf_8_string_8 (a_activity.name)) + ", ")
			if a_activity.has_resource ({TM_RESOURCE}.Cpu) then
				Result.append (a_activity.cpu_cores.out)
			else
				Result.append ("NULL")
			end
			Result.append (", " + a_activity.cpu_status.out + ", ")
			if a_activity.has_resource ({TM_RESOURCE}.Io_total) then
				Result.append (a_activity.io_read_bps.out + ", " + a_activity.io_write_bps.out)
			else
				Result.append ("NULL, NULL")
			end
			Result.append (", " + a_activity.io_status.out + ", ")
			if a_activity.has_resource ({TM_RESOURCE}.Memory) then
				Result.append (a_activity.private_bytes.out + ", " + a_activity.working_set.out)
			else
				Result.append ("NULL, NULL")
			end
			Result.append (", " + a_activity.memory_status.out + ")")
		end

	append_headline (a_sql: STRING_8; a_reading: TM_READING)
			-- Append "value, status, " for a headline column pair; NULL when not available.
		do
			if a_reading.is_available then
				a_sql.append (a_reading.value.out)
			else
				a_sql.append ("NULL")
			end
			a_sql.append (", " + a_reading.status.out + ", ")
		end

	busiest_disk (a_readings: TM_READINGS): TM_READING
			-- The highest available disk busy reading; else the most useful reason; not supported when none stored.
		local
			l_one: TM_READING
		do
			create Result.make_not_supported
			across a_readings.instances ({TM_METRICS}.Disk_busy_pct) as ic loop
				l_one := a_readings.reading ({TM_METRICS}.Disk_busy_pct, ic)
				if l_one.is_available then
					if not Result.is_available or else l_one.value > Result.value then
						Result := l_one
					end
				elseif not Result.is_available and then l_one.status /= {TM_READING_STATUS}.Not_supported then
					Result := l_one
				end
			end
		end

	quoted (a_text: READABLE_STRING_8): STRING_8
			-- `a_text' as an SQL string literal.
		do
			create Result.make (a_text.count + 8)
			Result.append_character ('%'')
			across a_text as ic loop
				if ic = '%'' then
					Result.append_character ('%'')
				end
				Result.append_character (ic)
			end
			Result.append_character ('%'')
		end

	payload_of (a_row: SIMPLE_SQL_ROW): STRING_8
			-- The payload column inflated back to the codec's UTF-8 text; empty when it does not inflate.
		local
			l_bytes: STRING_8
			i: INTEGER
		do
			create Result.make_empty
			if attached a_row.blob_value ("payload") as al_blob then
				create l_bytes.make (al_blob.count)
				from i := 0 until i = al_blob.count loop
					l_bytes.append_character (al_blob.read_natural_8 (i).to_character_8)
					i := i + 1
				end
				if attached inflated (l_bytes) as al_text then
					Result := al_text
				end
			end
		end

	inflated (a_bytes: STRING_8): detachable STRING_8
			-- `a_bytes' decompressed; Void when they are not zlib data.
		local
			l_failed: BOOLEAN
		do
			if not l_failed and then not a_bytes.is_empty then
				Result := compressor.decompress_string (a_bytes)
			end
		rescue
			l_failed := True
			retry
		end

	hex_literal (a_bytes: STRING_8): STRING_8
			-- `a_bytes' as an SQL blob literal X'...'.
		local
			l_digits: STRING_8
		do
			l_digits := "0123456789ABCDEF"
			create Result.make (a_bytes.count * 2 + 3)
			Result.append ("X'")
			across a_bytes as ic loop
				Result.append_character (l_digits [ic.code // 16 + 1])
				Result.append_character (l_digits [ic.code \\ 16 + 1])
			end
			Result.append_character ('%'')
		end

	decoded (a_text: STRING_8): detachable TM_FRAME
			-- Frame of payload `a_text'; Void, with `last_error' set, when it does not decode.
		do
			codec.decode (a_text)
			if codec.has_frame then
				Result := codec.last_frame
			elseif last_error.is_empty then
				last_error.append ({STRING_32} "damaged frame in the recording: " + codec.last_error)
			end
		end

	entries_where (a_condition: READABLE_STRING_8): ARRAYED_LIST [TM_TRACE_ENTRY]
			-- Bookkeeping of the frames meeting `a_condition', oldest first.
		require
			open: is_open
		local
			l_rows: SIMPLE_SQL_RESULT
			l_tier: INTEGER
		do
			l_rows := rows ("SELECT id, start_ticks, end_ticks, tier, pinned, discontinuity FROM frames WHERE " + a_condition
				+ " ORDER BY start_ticks")
			create Result.make (l_rows.count)
			across l_rows.rows as ic loop
				l_tier := ic.integer_value ("tier")
				if ic.integer_64_value ("id") > 0 and ic.integer_64_value ("end_ticks") > ic.integer_64_value ("start_ticks")
						and policy.is_valid_tier (l_tier) then
					Result.extend (create {TM_TRACE_ENTRY}.make (ic.integer_64_value ("id"), ic.integer_64_value ("start_ticks"),
						ic.integer_64_value ("end_ticks"), l_tier, ic.integer_value ("pinned") /= 0, ic.integer_value ("discontinuity") /= 0))
				end
			end
		end

	apply_group (a_group: TM_MERGE_GROUP)
			-- Move or merge one retention group into its target tier.
		require
			writable: is_writable
		local
			l_frames: ARRAYED_LIST [TM_FRAME]
			l_rows: SIMPLE_SQL_RESULT
			l_ids: STRING_8
		do
			create l_ids.make (a_group.ids.count * 12)
			across a_group.ids as ic loop
				if not l_ids.is_empty then
					l_ids.append (", ")
				end
				l_ids.append (ic.out)
			end
			if a_group.is_move_only then
				exec ("UPDATE frames SET tier = " + a_group.target_tier.out + " WHERE id = " + l_ids)
			else
				l_rows := rows ("SELECT payload FROM frames WHERE id IN (" + l_ids + ") ORDER BY start_ticks")
				create l_frames.make (l_rows.count)
				across l_rows.rows as ic loop
					if attached decoded (payload_of (ic)) as al_frame then
						l_frames.extend (al_frame)
					end
				end
				if l_frames.count = a_group.ids.count and then mergeable (l_frames) then
					exec ("DELETE FROM frames WHERE id IN (" + l_ids + ")")
					insert_frame (merger.merged (l_frames), a_group.target_tier)
				else
						-- Keep the data at its own resolution rather than lose it.
					last_error.wipe_out
					exec ("UPDATE frames SET tier = " + a_group.target_tier.out + " WHERE id IN (" + l_ids + ")")
				end
			end
		end

	mergeable (a_frames: ARRAYED_LIST [TM_FRAME]): BOOLEAN
			-- Do `a_frames' meet the merger's precondition?
		do
			Result := not a_frames.is_empty
				and then across 2 |..| a_frames.count as ic all a_frames [ic].start_ticks >= a_frames [ic - 1].end_ticks end
				and then across a_frames as ic all not ic.is_discontinuity end
				and then across a_frames as ic all ic.logical_processors = a_frames.first.logical_processors end
		end

	enforce_cap
			-- Delete the oldest unpinned frames, never the newest, until the used size fits the cap.
		require
			writable: is_writable
		local
			l_done: BOOLEAN
		do
			cap_deletions := 0
			from
			until
				l_done or not last_error.is_empty or else size_bytes <= policy.size_cap_bytes
			loop
				exec ("DELETE FROM frames WHERE id IN (SELECT id FROM frames WHERE pinned = 0 AND end_ticks < "
					+ latest_ticks.out + " ORDER BY start_ticks LIMIT 25)")
				l_done := db.modified_count = 0
				if not l_done then
					cap_deletions := cap_deletions + db.modified_count
				end
			end
		end

	cap_deletions: INTEGER
			-- Frames the last `enforce_cap' deleted.

invariant
	pending_bounded: pending >= 0 and pending < Commit_every
	pending_only_when_writable: pending > 0 implies is_writable
	open_has_connection: is_open = (database /= Void)

end
