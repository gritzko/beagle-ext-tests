# be/test — data-driven JS-vs-native parity cases for the beagle-ext (`be/`)
# resident loop.  Each <verb>/<case>/run.sh is a differential harness: it runs
# native `be <verb>` and bareword `jab <verb>` (the loop, resolved via jab's
# upward be/-scan) and asserts byte-parity.  Registered as be-js-<verb>-<case>.
#
# The toolchain (be, jab, keeper) is EXTERNAL — ${BEAGLE_BIN_DIR}, built by the
# beagle submodule.  The harness plants a `be -> <be/>` shard symlink above its
# scratch worktrees so bareword `jab <verb>` resolves the extension.

# Scratch TMP MUST live outside this tree: `be` walks the cwd up for a `.be`
# anchor, and a scratch wt under the source tree would glue onto the project's
# own store.  $HOME-rooted (ext4) so the store mmaps + ssh path resolution work.
set(BE_TEST_TMP "$ENV{HOME}/tmp/be-ext-tests" CACHE PATH
    "scratch root for be/test parity cases")
file(MAKE_DIRECTORY "${BE_TEST_TMP}")

# Known JS-port gaps (xfail): the loop's view/verb output diverges from native
# until the respective JSQUE conversion lands.  Tracked here; drop an entry as
# its conversion makes the case pass.  NOT harness bugs — real product gaps.
set(_BE_WILL_FAIL
    be-js-spot-search                 # JS grep omits the `grep ` banner prefix
    be-js-spot-submount               # + JS grep does not recurse into submounts
    be-js-regex-regex                 # JS grep banner (regex scheme)
    be-js-diff-01-3revs               # JS diff view output diverges from native
    be-js-diff-02-divergent-children
    be-js-diff-03-stock-context
    be-js-diff-08-sub-pin-bump-gitlink
    be-js-diff-11-file-scope-full
    be-js-bro-color                   # JS bro-view rendering differs
    be-js-bro-view
    be-js-put-bare                    # bare `jab put` (stage-all) emits nothing
)

# Glob <verb>/<case>/run.sh (CONFIGURE_DEPENDS → new case dirs picked up on
# rebuild).  lib/ dirs carry no run.sh, so they are naturally excluded.
file(GLOB _be_runs CONFIGURE_DEPENDS
    RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/*/*/run.sh")

foreach(_run ${_be_runs})
    get_filename_component(_case_dir "${_run}" DIRECTORY)        # <verb>/<case>
    get_filename_component(_case "${_case_dir}" NAME)
    get_filename_component(_verb_dir "${_case_dir}" DIRECTORY)
    get_filename_component(_verb "${_verb_dir}" NAME)
    if (_verb STREQUAL "lib")
        continue()
    endif()
    set(_name "be-js-${_verb}-${_case}")
    add_test(NAME ${_name}
        COMMAND sh "${CMAKE_CURRENT_SOURCE_DIR}/${_run}"
        WORKING_DIRECTORY "${BE_TEST_TMP}")
    set_tests_properties(${_name} PROPERTIES
        ENVIRONMENT "BIN=${BEAGLE_BIN_DIR};TMP=${BE_TEST_TMP};ASAN_OPTIONS=detect_leaks=0"
        TIMEOUT 90)
    if (_name IN_LIST _BE_WILL_FAIL)
        set_tests_properties(${_name} PROPERTIES WILL_FAIL TRUE)
    endif()
endforeach()

# Top-level jab unit tests (run the script directly; be-relative requires
# resolve via the script's own upward be/-scan).  Only the landed, general
# ones are registered.  barrier/loop/resolve/emit are dev repro tests pinned to
# in-flight ticket worktrees (~/todo/JSQUE-002/004/005/006) loading code "not in
# the live shard" — NOT landed-suite material, so they are intentionally omitted.
foreach(_unit store ulog)
    add_test(NAME be-js-unit-${_unit}
        COMMAND "${BEAGLE_BIN_DIR}/jab" "${CMAKE_CURRENT_SOURCE_DIR}/${_unit}.js"
        WORKING_DIRECTORY "${BE_TEST_TMP}")
    set_tests_properties(be-js-unit-${_unit} PROPERTIES
        ENVIRONMENT "TMP=${BE_TEST_TMP};ASAN_OPTIONS=detect_leaks=0"
        TIMEOUT 60)
endforeach()
