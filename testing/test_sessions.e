note
	description: "Phase 3 slice 6: sessions for the Users tab (read live; no session is acted on)."
	author: "Larry Rix"
	testing: "covers"

class
	TEST_SESSIONS

inherit
	TM_TEST_SET

feature -- Tests

	test_this_session_is_listed_with_its_user
		local
			l_list: TM_SESSION_LIST
		do
			create l_list.make
			l_list.refresh (Void)
			assert_true ("this session listed", across l_list.sessions as ic some ic.id = l_list.current_session end)
			assert_true ("with a DOMAIN\user name", across l_list.sessions as ic some
				ic.id = l_list.current_session and then ic.user.has ('\') end)
		end

	test_totals_come_from_the_frame
		local
			l_list: TM_SESSION_LIST
			l_activities: ARRAYED_LIST [TM_PROCESS_ACTIVITY]
			l_frame: TM_FRAME
		do
			create l_list.make
			create l_activities.make (2)
			l_activities.extend (activity (11, l_list.current_session, 0.5))
			l_activities.extend (activity (12, l_list.current_session, 1.5))
			create l_frame.make (Base_utc, Base_utc + One_second, One_second, 4, False, create {TM_READINGS}.make, l_activities,
				create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0), create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
			l_list.refresh (l_frame)
			across l_list.sessions as ic loop
				if ic.id = l_list.current_session then
					assert_integers_equal ("two processes", 2, ic.process_count)
					assert_reals_equal ("2 cores of 4 = 50%%", 50.0, ic.cpu_percent, 1.0e-9)
				end
			end
		end

feature {NONE} -- Fixtures

	activity (a_pid: INTEGER_64; a_session: INTEGER; a_cores: REAL_64): TM_PROCESS_ACTIVITY
		do
			create Result.make_decoded (id (a_pid, 1000 + a_pid), {STRING_32} "p.exe", 4, a_session, 1, 10, False, 4,
				{TM_READING_STATUS}.Available, a_cores, {TM_READING_STATUS}.Available, 1024, 1024,
				{TM_READING_STATUS}.Available, 0.0, 0.0)
		end

end
