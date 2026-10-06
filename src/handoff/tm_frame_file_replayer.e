note
	description: "[
		Replay worker (R-2): feeds frames from a file of TMF1 blocks into the
		slot, one per interval, in place of sampling. The same file gives the
		same screen every run, which is what the GUI phase gates photograph
		(intent Q4). Runs on its own processor, with the worker's slot rules.
	]"
	author: "Larry Rix"

class
	TM_FRAME_FILE_REPLAYER

create
	make

feature {NONE} -- Initialization

	make (a_path: separate READABLE_STRING_32; a_interval_ms: INTEGER)
			-- Replayer of the frames in `a_path', one every `a_interval_ms'.
		require
			path_given: not a_path.is_empty
			sane_interval: a_interval_ms >= 50 and a_interval_ms <= 60_000
		do
			create path.make_from_separate (a_path)
			interval_ms := a_interval_ms
			create codec.make
		ensure
			kept: interval_ms = a_interval_ms
			idle: not is_running and frames_sent = 0
		end

feature -- Access

	path: STRING_32
			-- File of encoded frames.

	interval_ms: INTEGER
			-- Pause between frames.

	frames_sent: INTEGER
			-- Frames put into the slot so far.

	slot: detachable separate TM_FRAME_SLOT
			-- Where frames go.

feature -- Status report

	is_running: BOOLEAN
			-- Is `run' looping?

feature -- Element change

	attach_slot (a_slot: separate TM_FRAME_SLOT)
			-- Deliver frames to `a_slot'.
		require
			not_running: not is_running
		do
			slot := a_slot
		ensure
			attached_slot: slot = a_slot
		end

feature -- Execution

	run
			-- Put each frame of `path' into the slot at `interval_ms', until the
			-- file ends or the slot asks to stop. An unreadable file is reported
			-- through the slot's failure text.
		require
			has_slot: attached slot
			not_running: not is_running
		local
			l_clock: TM_SYSTEM_CLOCK
		do
			if attached slot as al_slot then
				is_running := True
				load_file
				if attached file_contents as al_text then
					if attached codec.frame_texts_in (al_text) as al_frames and then not al_frames.is_empty then
						create l_clock.make
						across al_frames as ic until should_stop (al_slot) loop
							deposit (al_slot, ic)
							frames_sent := frames_sent + 1
							l_clock.sleep_ms (interval_ms)
						end
					else
						report_failure (al_slot, {STRING_32} "no TMF1 frames in " + path)
					end
				else
					report_failure (al_slot, {STRING_32} "cannot read " + path)
				end
				report_stopped (al_slot)
				stop_reported := True
				is_running := False
			end
		ensure
			stopped: not is_running
			slot_told: stop_reported
		end

feature -- Status report (after run)

	stop_reported: BOOLEAN
			-- Did `run' tell the slot it stopped (put_stopped)?

feature {NONE} -- Slot calls: each locks the slot for one short call

	deposit (a_slot: separate TM_FRAME_SLOT; a_text: STRING_8)
		require
			given: not a_text.is_empty
		do
			a_slot.put_frame (a_text)
		end

	report_failure (a_slot: separate TM_FRAME_SLOT; a_text: STRING_32)
		require
			given: not a_text.is_empty
		do
			a_slot.put_failure (a_text)
		end

	report_stopped (a_slot: separate TM_FRAME_SLOT)
		do
			a_slot.put_stopped
		end

	should_stop (a_slot: separate TM_FRAME_SLOT): BOOLEAN
		do
			Result := a_slot.stop_requested
		end

feature {NONE} -- Implementation

	file_contents: detachable STRING_8
			-- Contents of `path' read by `load_file'; Void when it could not be read.

	load_file
			-- Read `path' into `file_contents', or leave it Void when the file cannot be read.
		local
			l_file: RAW_FILE
			l_retried: BOOLEAN
		do
			file_contents := Void
			if not l_retried then
				create l_file.make_with_name (path)
				if l_file.exists and then l_file.is_readable then
					l_file.open_read
					l_file.read_stream (l_file.count)
					file_contents := l_file.last_string.twin
					l_file.close
				end
			end
		rescue
			l_retried := True
			retry
		end

	codec: TM_FRAME_CODEC

invariant
	sane_interval: interval_ms >= 50 and interval_ms <= 60_000
	sent_non_negative: frames_sent >= 0

end
