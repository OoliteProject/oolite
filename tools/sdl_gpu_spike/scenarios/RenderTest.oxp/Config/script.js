/*
    Renderer regression scenario, run by game-snapshot.py --scenario.

    Loaded through OO_ADDITIONALADDONSDIRS only for tests. World scripts only
    start with a game, so game-snapshot.py takes the title and new-game
    snapshots and starts the game itself; this script then drives the game
    with console.simulateKey (debug console, debug builds) and snapshots a
    fixed set of screens. Every step is timed from the startUpComplete event,
    which comes at the same tick on every run, and with OO_DETERMINISTIC_TEST
    each tick advances the clock by exactly 1/60 s, so the same frames are
    captured every time.

    Snapshots, in order:
    1 title, 2 new game, 3 status, 4 manifest, 5 short-range chart,
    6 long-range chart, 7 system data, 8 market, 9 and 10 flight, 2 s and
    4 s after the launch tunnel ends, 11 aft view, 12 port view,
    13 starboard view, 14 a ship spawned ahead, 15 firing lasers at it,
    16 its explosion, 17 the debris. Then the game quits.

    ES5 only, as the game's JavaScript engine requires.
*/
"use strict";

this.name = "oolite-render-test";

/*  Scripts such as the populator use Math.random, which SpiderMonkey seeds
    from the clock. Replace it with a fixed-seed generator (a 32-bit
    xorshift) so systems are populated the same way on every run. This
    runs when the script loads, before the system is set up.
*/
(function () {
    var state = 0x2545F491;
    Math.random = function () {
        state ^= state << 13;
        state ^= state >>> 17;
        state ^= state << 5;
        return (state >>> 0) / 4294967296;
    };
}());

this.startUpComplete = function () {
    var steps = [
        { at: 2.0, snap: true },
        { at: 2.5, key: "F5" },
        { at: 4.0, snap: true },
        { at: 4.5, key: "F6" },
        { at: 6.0, snap: true },
        { at: 6.5, key: "F6" },
        { at: 8.0, snap: true },
        { at: 8.5, key: "F7" },
        { at: 10.0, snap: true },
        { at: 10.5, key: "F8" },
        { at: 12.0, snap: true },
        { at: 12.5, key: "F1" }
    ];
    var flightSteps = [
        { at: 2.0, snap: true },
        { at: 4.0, snap: true },
        { at: 4.5, key: "F2" },
        { at: 5.5, snap: true },
        { at: 6.0, key: "F3" },
        { at: 7.0, snap: true },
        { at: 7.5, key: "F4" },
        { at: 8.5, snap: true },
        { at: 9.0, key: "F1" },
        { at: 9.5, spawn: true },
        { at: 10.5, snap: true },
        { at: 11.0, key: "A", hold: 0.6 },
        { at: 11.3, snap: true },
        { at: 12.0, explode: true },
        { at: 12.4, snap: true },
        { at: 13.5, snap: true },
        { at: 14.0, quit: true }
    ];
    var start = clock.absoluteSeconds, next = 0, keyName = null, keyUpAt = 0, launchedAt = -1, flightNext = 0, target = null;
    var callback = addFrameCallback(function () {
        var now = clock.absoluteSeconds - start;
        if (keyName !== null && now >= keyUpAt) {
            console.simulateKey(keyName, false);
            keyName = null;
        }
        while (next < steps.length && now >= steps[next].at) {
            var step = steps[next++];
            if (step.snap) {
                takeSnapShot();
            } else {
                console.simulateKey(step.key, true);
                keyName = step.key;
                keyUpAt = now + 0.2;
            }
        }
        if (next >= steps.length && player.ship.status === "STATUS_IN_FLIGHT") {
            if (launchedAt < 0) {
                launchedAt = now;
            }
            var t = now - launchedAt;
            while (flightNext < flightSteps.length && t >= flightSteps[flightNext].at) {
                var fs = flightSteps[flightNext++];
                if (fs.snap) {
                    takeSnapShot();
                }
                if (fs.key) {
                    console.simulateKey(fs.key, true);
                    keyName = fs.key;
                    keyUpAt = now + (fs.hold || 0.2);
                }
                if (fs.spawn) {
                    var ahead = player.ship.position.add(player.ship.vectorForward.multiply(350));
                    target = (system.addShips("trader", 1, ahead, 0) || [])[0];
                    if (target) {
                        target.orientation = player.ship.orientation;
                        target.AIScript.oolite_priorityai = null;
                        target.switchAI("nullAI.plist");
                        target.velocity = player.ship.velocity;
                        target.desiredSpeed = player.ship.speed;
                    }
                }
                if (fs.explode && target && target.isValid) {
                    target.explode();
                }
                if (fs.quit) {
                    removeFrameCallback(callback);
                    log("renderTest", "done");
                    quitGame();
                }
            }
        }
    });
    log("renderTest", "scenario started");
};
