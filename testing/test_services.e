note
	description: "[
		Phase 3 slice 4: the services table, read live and machine-neutral.
		Nothing here starts or stops a real service: actions are tried only on
		a service that does not exist, so a run as administrator is harmless.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_SERVICES

inherit
	TM_TEST_SET

feature -- Tests

	test_services_are_listed
		local
			l_table: TM_SERVICE_TABLE
		do
			create l_table.make
			l_table.refresh
			assert_string_empty ({STRING_32} "read: " + l_table.last_error, l_table.last_error)
			assert_true ("a Windows has many services: " + l_table.services.count.out, l_table.services.count > 50)
			if attached l_table.service_named ({STRING_32} "EventLog") as al_log then
				assert_true ("the event log runs", al_log.is_running)
				assert_true ("in a process", al_log.pid > 0)
				assert_true ("start type read", al_log.start_type >= 0)
				assert_string_not_empty ("named for people", al_log.display_name)
			else
				assert_true ("EventLog listed", False)
			end
		end

	test_start_types_are_remembered
		local
			l_table: TM_SERVICE_TABLE
		do
			create l_table.make
			l_table.refresh
			l_table.refresh
			if attached l_table.service_named ({STRING_32} "EventLog") as al_log then
				assert_true ("still known on the second refresh", al_log.start_type >= 0)
			end
		end

	test_actions_on_a_missing_service_are_refused
		local
			l_table: TM_SERVICE_TABLE
			l_result: TM_ACTION_RESULT
		do
			create l_table.make
			l_result := l_table.stop ({STRING_32} "simple_taskman_no_such_service")
			assert_false ("refused", l_result.succeeded)
			assert_string_contains ("says why", l_result.reason, "no such service")
			l_result := l_table.restart ({STRING_32} "simple_taskman_no_such_service")
			assert_false ("no pending restart", l_table.restart_pending ({STRING_32} "simple_taskman_no_such_service"))
		end

	test_descriptions_read
		local
			l_table: TM_SERVICE_TABLE
		do
			create l_table.make
			assert_string_not_empty ("EventLog describes itself", l_table.description ({STRING_32} "EventLog"))
		end

end
