"""Regression test: an array where a script method reads a dictionary is a script error.

mission.markSystem(), mission.unmarkSystem(), Ship.setMaterials() and Ship.setShaders() read keys
from the object they are given. In 1.93 an array there raises a native exception (a dictionary
method sent to an array), and the script gets an error; the method sweep in upstream's parity
probe (tools/js-parity, "arr" column) records that. The C++ build read the array as an empty
dictionary and returned normally. Spec 012, triage run 1, row 4.

setShaders() reads its argument only while shaders are on, so with shaders off it returns
normally, as 1.93 does.
"""

SCENARIO_SAVE = "Resources/Scenarios/oolite-standard.oolite-save"

# Calls the method and says how it ended: "returned" or "threw: <message>".
OUTCOME_JS = (
    "(function(){ try { %s; return 'returned'; }"
    " catch (e) { return 'threw: ' + e.message; } })()"
)

SHADERS_ON_JS = (
    "['DETAIL_LEVEL_SHADERS', 'DETAIL_LEVEL_EXTRAS']"
    ".indexOf(oolite.gameSettings.detailLevel) >= 0"
)


def _outcome(console, call):
    return console.evaluate(OUTCOME_JS % call).strip()


def _assert_native_exception(console, call):
    outcome = _outcome(console, call)
    assert outcome.startswith("threw: Native exception"), f"{call}: {outcome}"


def test_an_array_marker_is_a_script_error(world):
    console = world.start(seed=1, load_save=SCENARIO_SAVE)
    _assert_native_exception(console, "mission.markSystem([1, 2])")
    _assert_native_exception(console, "mission.unmarkSystem([1, 2])")


def test_an_object_marker_still_marks_and_unmarks(world):
    console = world.start(seed=1, load_save=SCENARIO_SAVE)
    marker = "{system: 7, name: 'test-012'}"
    assert _outcome(console, f"mission.markSystem({marker})") == "returned"
    assert console.evaluate(
        "mission.markedSystems.some(function(m) { return m.name == 'test-012'; })"
    ).strip() == "true"
    assert console.evaluate(f"mission.unmarkSystem({marker})").strip() == "true"


def test_array_materials_are_a_script_error(world):
    console = world.start(seed=1, load_save=SCENARIO_SAVE)
    _assert_native_exception(console, "player.ship.setMaterials([1, 2])")


def test_array_shaders_are_a_script_error_while_shaders_are_on(world):
    console = world.start(seed=1, load_save=SCENARIO_SAVE)
    if console.evaluate(SHADERS_ON_JS).strip() == "true":
        _assert_native_exception(console, "player.ship.setShaders([1, 2])")
    else:
        assert _outcome(console, "player.ship.setShaders([1, 2])") == "returned"
