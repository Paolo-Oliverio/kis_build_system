# tests/test_utils/test_regex_escape.cmake

# 1. Include the test_utilities and the module to test
include("${CMAKE_CURRENT_LIST_DIR}/../test_utilities.cmake")
include(utils)

# 2. Define test cases
message(STATUS "Running test: kis_regex_escape")

# --- Basic Escaping ---
kis_regex_escape(result "abc.def")
assert_equal("${result}" "abc\\.def")

kis_regex_escape(result "a+b*c?")
assert_equal("${result}" "a\\+b\\*c\\?")

kis_regex_escape(result "price{1,2}")
assert_equal("${result}" "price\\{1,2\\}")

kis_regex_escape(result "github.com/user/repo.git")
assert_equal("${result}" "github\\.com/user/repo\\.git")

kis_regex_escape(result "https://github.com/user/repo.git")
assert_equal("${result}" "https://github\\.com/user/repo\\.git")

kis_regex_escape(result "C:\\Program Files\\Test")
assert_equal("${result}" "C:\\\\Program Files\\\\Test")

kis_regex_escape(result "(foo|bar)^$[abc]")
assert_equal("${result}" "\\(foo\\|bar\\)\\^\\$\\[abc\\]")

message(STATUS "PASS: kis_regex_escape")