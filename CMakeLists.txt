# be/test — data-driven cases for the beagle-ext (`be/`) resident loop.  Each
# <verb>/<case>/run.sh runs bareword `jab <verb>` (the loop, resolved via jab's
# upward be/-scan).  JAB-003: converted verbs now emit TRUE HUNKS, so jab-vs-
# native-`be` parity is RETIRED — cases assert jab's output against a committed
# per-case GOLDEN snapshot (lib/golden.sh).  Registered as be-js-<verb>-<case>.
#
# The toolchain (be, jab, keeper) is EXTERNAL — ${BEAGLE_BIN_DIR}, built by the
# beagle submodule.  The harness plants a `be -> <be/>` shard symlink above its
# scratch worktrees so bareword `jab <verb>` resolves the extension.

# Scratch TMP MUST live outside this tree: `be` walks the cwd up for a `.be`
# anchor, and a scratch wt under the source tree would glue onto the project's
# own store.  $HOME-rooted (ext4) so the store mmaps + ssh path resolution work.
set(BE_TEST_TMP "$ENV{HOME}/tmp/be-ext-tests" CACHE PATH
    "scratch root for be/test cases")
file(MAKE_DIRECTORY "${BE_TEST_TMP}")

# PUT-006 harness: each case pid-stamps + cleans its OWN $TMP/$$ scratch, so the
# shared root can vanish between configure and a `ctest` run — then the
# WORKING_DIRECTORY cd fails the WHOLE suite ("Not Run") before any run.sh.  A
# SETUP fixture re-creates the root; every case declares FIXTURES_REQUIRED be_tmp.
add_test(NAME be-js-tmp-setup
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${BE_TEST_TMP}")
set_tests_properties(be-js-tmp-setup PROPERTIES FIXTURES_SETUP be_tmp)

# Known JS-port gaps (xfail): the loop's view/verb output diverges from native
# until the respective JSQUE conversion lands.  Tracked here; drop an entry as
# its conversion makes the case pass.  NOT harness bugs — real product gaps.
set(_BE_WILL_FAIL
    # SUBS-046: be-js-spot-submount now PASSES (local sub mount reuses the store,
    # no keeper) — dropped from xfail per the "drop an entry when it passes" rule.
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
        ENVIRONMENT "BIN=${BEAGLE_BIN_DIR};JABC=${JAB_BIN};TMP=${BE_TEST_TMP};ASAN_OPTIONS=detect_leaks=0"
        FIXTURES_REQUIRED be_tmp
        TIMEOUT 90)
    if (_name IN_LIST _BE_WILL_FAIL)
        set_tests_properties(${_name} PROPERTIES WILL_FAIL TRUE)
    endif()
endforeach()

# GIT-012 wire cases (test/wire/<case>): the glob above already registers them
# as be-js-wire-<case>.  The two TREADMILL cases (big-ssh/big-http) clone the
# real git source tree — slow + heavy — so tag them with the `big` LABEL (so
# `ctest -L big` selects them and `ctest -LE big` excludes them) and grant a
# longer TIMEOUT than the 90 s default.  lib/wirecase.sh carries no run.sh, so
# it is never registered as a case.
foreach(_big wire-big-ssh wire-big-http)
    if (TEST be-js-${_big})
        set_tests_properties(be-js-${_big} PROPERTIES LABELS "big;wire" TIMEOUT 300)
    endif()
endforeach()
#  GIT-013/014 PUSH cases (wire/<case>): post/put receive-pack over ssh + http.
#  Same `wire` label + 120 s timeout as the fetch cases; SKIP cleanly without
#  ssh-to-localhost / python3 / curl, so a no-net box reports green-skips.
foreach(_sm wire-ssh-clone wire-ssh-update wire-ssh-incremental
            wire-http-clone wire-http-update wire-http-incremental
            wire-push-ssh wire-push-http wire-push-nonff
            wire-put-force-ssh wire-put-force-http wire-put-dis011)
    if (TEST be-js-${_sm})
        set_tests_properties(be-js-${_sm} PROPERTIES LABELS "wire" TIMEOUT 120)
    endif()
endforeach()

# Top-level jab unit tests (run the script directly; be-relative requires
# resolve via the script's own upward be/-scan).  Only the landed, general
# ones are registered.  barrier/loop/resolve/emit are dev repro tests pinned to
# in-flight ticket worktrees (~/todo/JSQUE-002/004/005/006) loading code "not in
# the live shard" — NOT landed-suite material, so they are intentionally omitted.
foreach(_unit store ulog ingest idxmaint packlog patchband wire wirepush
        submount uri checkout_guard submount_guard stage_guard resolve_confine)
    add_test(NAME be-js-unit-${_unit}
        COMMAND "${JAB_BIN}" "${CMAKE_CURRENT_SOURCE_DIR}/${_unit}.js"
        WORKING_DIRECTORY "${BE_TEST_TMP}")
    set_tests_properties(be-js-unit-${_unit} PROPERTIES
        ENVIRONMENT "TMP=${BE_TEST_TMP};ASAN_OPTIONS=detect_leaks=0"
        FIXTURES_REQUIRED be_tmp
        TIMEOUT 60)
endforeach()

# Subdir unit tests (test/<topic>/<unit>.js).  LOG-001: log.js follows
# non-spine (merge 2nd+) parents and greys them.  Same direct-script harness.
foreach(_sub log/nonspine)
    string(REPLACE "/" "-" _subname "${_sub}")
    add_test(NAME be-js-unit-${_subname}
        COMMAND "${JAB_BIN}" "${CMAKE_CURRENT_SOURCE_DIR}/${_sub}.js"
        WORKING_DIRECTORY "${BE_TEST_TMP}")
    set_tests_properties(be-js-unit-${_subname} PROPERTIES
        ENVIRONMENT "TMP=${BE_TEST_TMP};ASAN_OPTIONS=detect_leaks=0"
        FIXTURES_REQUIRED be_tmp
        TIMEOUT 60)
endforeach()
