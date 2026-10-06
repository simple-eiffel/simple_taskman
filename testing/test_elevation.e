note
	description: "[
		Slice G: administrator rights and the Ctrl+Shift+Esc switch. The switch
		is only exercised when this run is NOT elevated, where it must be
		refused; an elevated run never changes the system here.
	]"
	author: "Larry Rix"
	testing: "covers"

class
	TEST_ELEVATION

inherit
	TM_TEST_SET

feature -- Tests

	test_program_path_is_this_executable
		do
			assert_true ("an exe", (create {TM_ELEVATION}).program_path.as_lower.ends_with ({STRING_32} ".exe"))
		end

	test_switch_needs_administrator
		local
			l_elevation: TM_ELEVATION
			l_result: TM_ACTION_RESULT
		do
			create l_elevation
			if not l_elevation.is_elevated then
				l_result := l_elevation.set_ctrl_shift_esc (True, l_elevation.program_path)
				assert_false ("refused without admin", l_result.succeeded)
				assert_string_contains ("says how", l_result.reason, "Restart as administrator")
				assert_false ("Task Manager still opens", l_elevation.is_ctrl_shift_esc_ours)
			end
		end

end
