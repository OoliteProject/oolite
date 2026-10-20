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
    4 s after the launch tunnel ends. Then the game quits.

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
    var start = clock.absoluteSeconds, next = 0, keyName = null, keyUpAt = 0, launchedAt = -1, flightSnaps = 0;
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
            if ((flightSnaps === 0 && now >= launchedAt + 2.0) || (flightSnaps === 1 && now >= launchedAt + 4.0)) {
                takeSnapShot();
                flightSnaps++;
                if (flightSnaps === 2) {
                    removeFrameCallback(callback);
                    log("renderTest", "done");
                    quitGame();
                }
            }
        }
    });
    log("renderTest", "scenario started");
};
