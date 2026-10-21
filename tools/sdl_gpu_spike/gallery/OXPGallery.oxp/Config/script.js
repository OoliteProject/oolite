/*
    OXP shader gallery, run by game-snapshot.py --gallery <OXZ dir>.

    The OXZs come from fetch-gallery.py. Once the game starts, this script
    launches the player, then spawns each ship in kShips in turn ahead of
    the player, holds it still relative to the player, snapshots it and
    removes it. Timing and randomness are fixed as in RenderTest.oxp, so a
    GL build and an SDL_GPU build capture the same frames.

    ES5 only, as the game's JavaScript engine requires.
*/
"use strict";

this.name = "oolite-oxp-gallery";

// Ship keys, one per distinct model or shader. The core Viper, Cobra and
// Constrictor are there for Griff's retextures of them.
var kShips = [
    "griff_prototype_boa-NPC", "griff_anaconda-NPC", "griff_asp-NPC", "griff_boa_MK2-NPC",
    "griff_gecko-NPC", "griff_moray-NPC", "griff_python-NPC", "griff_python_blackdog-NPC",
    "viper", "cobra3-trader", "constrictor",
    "griff_wreckage_1", "griff_alloy_1", "griff_fridge",
    "cobra3-xt", "black_knave", "cougar_st", "cougar-alt",
    "RNRL_Stormbrewer-trader-alt", "RNRL_Stormbrewer-pirate"
];

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
    var start = clock.absoluteSeconds, launchPressed = false, keyUpAt = -1, launchedAt = -1;
    var index = 0, phase = 0, phaseAt = 0, ship = null, turned = false;
    var callback = addFrameCallback(function () {
        var now = clock.absoluteSeconds - start;
        if (keyUpAt >= 0 && now >= keyUpAt) {
            console.simulateKey("F1", false);
            keyUpAt = -1;
        }
        if (!launchPressed && now >= 2.0) {
            console.simulateKey("F1", true); // launch
            keyUpAt = now + 0.2;
            launchPressed = true;
        }
        if (player.ship.status !== "STATUS_IN_FLIGHT") {
            return;
        }
        if (launchedAt < 0) {
            launchedAt = now;
            phaseAt = now + 3.0;
        }
        if (!turned && now >= launchedAt + 2.0) {
            /*  Pitch up, so neither the planet ahead nor the station behind
                is in view: with these OXPs loaded the planet's clouds differ
                from run to run, while the star field doesn't.
            */
            var toPlanet = system.mainPlanet.position.subtract(player.ship.position).direction();
            var toStation = system.mainStation.position.subtract(player.ship.position).direction();
            player.ship.orientation = player.ship.orientation.rotate(player.ship.vectorRight, -Math.PI / 2);
            log("oxpGallery", "turned: forward . planet " + player.ship.vectorForward.dot(toPlanet).toFixed(3)
                + ", forward . station " + player.ship.vectorForward.dot(toStation).toFixed(3));
            turned = true;
        }
        if (ship && ship.isValid) {
            ship.velocity = player.ship.velocity;
        }
        if (now < phaseAt) {
            return;
        }
        if (index >= kShips.length) {
            removeFrameCallback(callback);
            log("oxpGallery", "done");
            quitGame();
            return;
        }
        if (phase === 0) {
            ship = (system.addShips("[" + kShips[index] + "]", 1, player.ship.position, 0) || [])[0];
            if (ship) {
                var distance = ship.collisionRadius * 2.2 + 20;
                ship.position = player.ship.position.add(player.ship.vectorForward.multiply(distance));
                // A three-quarter view: turned 130 degrees about the player's up axis.
                ship.orientation = player.ship.orientation.rotate(player.ship.vectorUp, 2.27);
                if (ship.AIScript) {
                    ship.AIScript.oolite_priorityai = null;
                }
                ship.switchAI("nullAI.plist");
                ship.velocity = player.ship.velocity;
                ship.desiredSpeed = player.ship.speed;
                log("oxpGallery", "ship " + (index + 1) + ": " + kShips[index] + ", radius " + ship.collisionRadius.toFixed(1));
            } else {
                log("oxpGallery", "ship " + (index + 1) + ": " + kShips[index] + " could not be added");
            }
            phase = 1;
            phaseAt = now + 1.2;
        } else if (phase === 1) {
            takeSnapShot();
            phase = 2;
            phaseAt = now + 0.3;
        } else {
            if (ship && ship.isValid) {
                ship.remove(true);
            }
            ship = null;
            index++;
            phase = 0;
            phaseAt = now + 0.3;
        }
    });
    log("oxpGallery", "gallery started");
};
