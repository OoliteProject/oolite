

How to run Oolite
-----------------

A folder has been created in Start -> Program Files called Oolite. This
folder has icons for running the game, the reference sheet, the Advice
for New Commanders guide, the link to the official Oolite website,a more
detailed ReadMe document in PDF format and an uninstall program.

To run the game, choose the Oolite icon in the Oolite folder.


The user preferences defaults file .GNUstepDefaults
-----------------------------------------------------------------------

The file <installation dir>/oolite.app/GNUstep/Defaults/.GNUstepDefaults
contains the current settings for fullscreen mode and display resolutions,
together with the user preference settings for sound volume, reduced
detail (Yes/No), wireframe graphics display (Yes/No) and the shader
effects level (Off, Simple, Full), in case your system supports shaders.
All these can be changed by either running the game and navigating to the
Game Options... menu ('F2' or '2' key, then select Game Options...), or
by directly editing the .GNUstepDefaults file. The recommended way to
change settings is to use the in-game menu. See below for examples of
editing the preferences file. Note that .GNUstepDefaults will not be
present after the game's installation. You will need to run Oolite at
least once to have it generated.


Switching between full screen and windowed mode, or changing resolution
-----------------------------------------------------------------------

If in doubt, delete .GNUstepDefaults and restart the game. That will start
you in windowed mode.

To change the full screen mode resolution, you can use the Game Options...
menu or alternatively edit the .GNUstepDefaults file by changing the
display_width and display_height values, and ensuring the fullscreen
property has a value of <*BY>.


.GNUstepDefaults Editing Examples
-----------------------------------------------------------------------

These settings will give a full screen display of 800x600, about one
third sound volume, reduced detail set to No, wireframe graphics set
to Yes and shader effects set to Simple:

{
    NSGlobalDomain = {
    };
    oolite.exe = {
    display_width = <*I800>;
    display_height = <*I600>;
    fullscreen = <*BY>;
    "reduced-detail-graphics" = <*BN>;
    "shader-effects-level" = <*I2>;
    volume_control = <*R0.26>;
    "wireframe-graphics" = <*BY>;
    };
}

And these settings will give a full screen display of 1400x1050,
full sound volume, reduced detail set to No, wireframe graphics
set to No and shader effects set to Full:

{
    NSGlobalDomain = {
    };
    oolite.exe = {
    display_width = <*I1400>;
    display_height = <*I1050>;
    fullscreen = <*BY>;
    "reduced-detail-graphics" = <*BN>;
    "shader-effects-level" = <*I3>;
    volume_control = <*R1>;
    "wireframe-graphics" = <*BN>;
    };
}


Tips
----

* Read the installed "Oolite reference sheet" PDF for the controls

* More detailed information about the game can be found inside the Acrobat
  PDF OoliteReadMe file, already installed in your root Oolite folder

* Use Shift+Escape to quit the game

* You can read the Advice for New Commanders at the bottom of this file for
  a quick introduction to the game, with hints and tips


Links
-----
Oolite website at: http://www.oolite.org

Oolite Message Board at: http://www.aegidian.org/bb

Oolite Development Project Page at: https://developer.berlios.de/projects/oolite-linux/

Browse the Oolite wiki at: http://wiki.alioth.net/index.php/Oolite_Main_Page

Get OXPs at: 	http://wiki.alioth.net/index.php/OXP











Advice for New Commanders*
by Disembodied, 24-Mar-2008
---------------------------

It is an ancient mariner, 
and he stoppeth one of three... 

All right there! You just got your pilot’s ticket. Can I just say that your zip-clip
there doesn’t do you justice? You’re itching to get off and out into the big black, I
can tell; but we just got a few final once-overs before I can stamp that thing legal.
Shall we? 

So. You got yourself a brand and shiny-new Cobra Mark III. Cowell and MgRath’s finest,
yes siree: more’n sixty years since the first one rolled off the line right here on Lave,
and it’s still one of the best. An all-round ship, you get me? It ain’t the fastest, and
it ain’t the strongest, nor the most killing neither, and it definitely ain’t the biggest,
by a long shot, but a sweet little number in her own right, no error. 

Let’s take a tour around... Hoo boy, she is mint, ain’t she! I just love that new-ship
smell. Take a sniff, go on: yeah, well, most of them long-chain monomers is carcinogenic,
so don’t you snort too deep... 

Hah! I’m just funnin’ ya, kid. If pulling a tick from sniffing the command console was all
a pilot had to worry about, life would be gravy! No, there’s more’n enough out there to kill
you plenty quick, if you don’t watch out, shiny new ship or no. 

I see a lot of blanks on this here board... I’m guessing your ship is, whadda they call it,
a basic model, yeah? Legal minimum? Uh-huh, I thought so. Man oh man, they shouldn’t oughta
let kids out in a machine like this; it’s a sin, is what it is. Some bandit takes a pop at
you, and what you got to hold your end up with? A Pulse Laser. A Pulse Laser’s one step up
from a penlight, kiddo. Oh, it’s a better defence than just harsh language, and there’s
always a chance you might be attacked by a really nervous pirate – but seriously: if you
ever want to shift that “Harmless” tag you better beef up your armaments, and soon! Beam
laser, minimum. Until then you’d best stick to the cop-end worlds: Democracies and Corporates,
Confederacies maybe if you’re feeling lucky, you hear me? You stay sharp, and maybe you’ll
stay alive.

See, right here is what I’m talking about: this is where you need to fit an ECM. Someone locks
a missile on you, you pop that sucker fast. Oh, I know there’s Hardheads out there, shielded
missiles proofed against countermeasures, but a good ECM can pop those too, if you’re lucky.
You get one of those running on you, you turn tail and run from it as fast as you can. A
warhead’s nasty, but nosense in giving it a kinetic advantage too, right? Keep slapping the ECM
as you go, if you’ve got the energy for it: if the first burst don’t kill it, maybe the next
one will.

Speaking of running... over here is where you’d control your Witchdrive Fuel Injectors, if’n
you had ‘em... dumps fuel straight from the tanks into the drive, and shoots you off like an
Oresquan on a hot date. Good for whatever ails ya, from pushing past a mass-lock to getting the
hell out of town!

Down here, now, this is your Fuel Scoop indicator... huh, “offline”, I see. Sure, sure, you
don’t think you’ll ever need to kiss the stars: why bother, when fuel’s cheaper than Celabiler
poetry? Well, maybe it’s true, and maybe it ain’t, but anyways this piece of kit scoops up more
than just sunshine. There’s scraps and salvage out there, kid, and good money to be had. Skim on
over the top and this puppy drops ‘em straight into the cargo bay. Pays for itself in no time.
Sweeps up Escape Pods, too: you get the chance to bring someone safe home, you take it – even if
it means dumping some of your own payload to take them on board. Look out for the other guys and
they’ll look out for you.

And... sweet Lord Giles on a gyrospider, they didn’t even fit you out with a Docking Computer!
“Optional Extra”, my shiny blue ass... Oh, sure, manual docking’s easy enough, but there’s a
knack to it. You gotta get that knack first, though. Practice it. Before you go anywhere,
practice it. Fly out to the station buoy, turn around and come back in again, until you got it
pat. And match the rotation: you put scrapes or dents or a big long greasy smear all over my bay,
and I will NOT be pleased...

Oh, there’s a whole bunch of other shit you can stick on here: a Scanner Targeting Enhancement,
for one, if you ever get yourself set up right for a firefight. Even before then, maybe: if you
can clock pirates before they start their run on you, that’s half the battle. Well, quarter of
the battle. Or a fifth. Some proportion, anyhow. The Advanced Space Compass, too, now that’s a
handy doodad to have on board. And an Extra Energy Unit to boost your recharge. And Shield
Boosters, now they’re a no-brainer. And – okay, most of this junk is too high-tech for Lave: you
can get most everything at Zaonce, though, just a wormhole away. Dull kinda burg, Zaonce, but
they know their quarks from their quaternions. Shouldn’t set you back more’n ten, twenty thou.

You got how much? One hundred creds. One ... hundred ... creds. Ayoha. All right then. Let’s
break it down. Your problem here is financial, not technical. Maybe at bottom it’s psychological,
but I’ll give you the benefit.

There’s two types of money, kid: fast, and slow. Fast money comes easy, and slow money comes hard.
The slow is sure and steady, though, and the fast, well, it might make you wish you had waited.
I’ll run you through them both, though, and you can make up your own mind.

First of all, for the fast money, there’s this sweet and cherry Cobra III: you sell it, right now,
you’ll net yourself enough to buy a second-hand ship with enough scratch left over for some half-
decent kit. ‘Course, some of these second-hand numbers are pretty, well, used, if you know what I 
mean, and come with problems of their own. I mean, you ever try to take a dump in a head designed
for some other guy’s anatomy? And the resale sucks, if’n you ever want to move on up. But it’s an
option.

Second, now, there’s the... ah, let me just check that we’re alone here... okay: there’s the Black
Monks. Great guys, I’d like to make that clear, absolutely: most fine and upstanding! They’ll be
happy to loan you what you need to get you started. They’re a not-for-profit organisation, a charity,
really, but what with overheads and all they do have to charge a wee bit of interest on any loans
they make: and they are keen – eager, even – to see that they get paid back. You take a loan from
them, you make every gram of cargo pay, every time. Work hard though and it can be done: in all my
years I’ve never met anyone who defaulted on a loan from the Bank of St Herod. Not one. Ever.

Slow money, now, that’s less chancy. You buy up what’s cheap, you take it to where it’s expensive,
and you sell it at a profit. Rinse and repeat. What’s cheap where, and what’s expensive? Supply and
demand, kid. Like the philosopher said, “it’s the economy, stupid”. Agricultural worlds produce raw
materials like minerals, metals and radioactives, and the bio-products like food, textiles, booze
and furs, too. Industrial planets make finished goods, like luxuries, computers and machinery. So
you take the produce of one and you sell it on the other, and chances are you’re making money on
the deal. Politics don’t matter squat: farmers need harvesters and factories need feedstock!

O’course, money matters: rich Industrials are rich because they’ve got the most efficient processes,
so not only do they make the cheapest products, their factories are the hungriest and they’ll pay
the best prices for raw materials. Poor Agriculturals, on the other hand, they’re most desperate for
fine articles and will scrape together whatever they can to pay for ‘em: meanwhile, they’ll offer
you the cheapest deals anywhere for what they make themselves. Which puts a vicious lock on the
poverty trap, but hey: nobody said life was fair. Folks like you who’ve climbed up the gravity well,
you’re just filling a need. Buy and sell between rich Industrials and poor Agriculturals, that’s my
advice! There’s money to be made elsewhere, no error, but those are the sweetest runs you’re likely
to hit on. Bulk is the key, kid: the more you carry, the more you make. This Cobra III here can take
twenty tons, right now: for just 400 creds more you can get a Cargo Bay Expansion to take you up to
thirty-five.That extra fifteen tons of space will pay for itself and more in one good run, if you
can fill it up.

It ain’t all bulk, though. Watch the board for cheap deals on precious metals and gemstones: they
might not offer the greatest profits, but they don’t take up any cargo space at all. See this safe
over here, behind this bulkhead? You take on platinum, or gold, or a sack of IOUN gemstones when
you’re docked, they go right in here. You can keep ‘em here as long as you like, until you find
somewhere to offload ‘em. Co-op rules stop you dropping too much of ‘em, or too much of anything,
come to that, in one station – so much for free trade! – but as a slow-burn money-maker there’s not
much to beat it. You can mine for ‘em yourself, if’n you get a Mining Laser and an Ore Processor to
go with your Fuel Scoop, and you don’t mind scraping carbon scoring off the scoop every few jumps.
Only don’t, for any sake, put the Mining Laser on the nose! It’s a tool, not a weapon. Or you can
just buy the shinies cheap off the miners direct, if you run across a Rock Hermit. Powerful fond of
liquor, Rock Hermits are, too.

What “other” products? What you winking for, kid? You mean slaves, narcotics and firearms? Why don’t
you just damn well say so? They ain’t illegal. They’s what we call controlled merchandise. Bring as
much of ‘em in as you want... what will get you into trouble with the Blues is shipping them out of
a main system station. But there’s plenty of other places to buy ‘em up, all nice and legal, along
with reg’lar trade goods, too. Some of the Commie worlds have Slap-Yous and Cee-Zed-Gee-Effs, whatever
the hell they all are, and Astro-Gulags too, which are just plain depressing. Some industrial
Dictatorship systems, they got Imperial AstroFactories, although some of ‘em seem to sell stuff they
don’t ever make... go figure. And some spots, if they got the population size to make it worthwhile,
there’s Convenience Stores way out by the Witchpoint. You want to give these guys a try, you sail on
in. Check the system prices first, note down what you got yourself, see what’s on offer, and do the
sums.

There’s long-range shipping contracts on offer, too, in some stations: F8-F8 will bring ‘em up, if
there’s any there. You buy the deal and then get paid a bonus if you make the delivery on time.
They’ll be out your price-range just now, and anyway most of ‘em call for a bigger cargo-hold than
a Cobra can carry. Keep an eye out for any you might be able to do, though; if you build a rep as a
reliable carrier then the jobs can get real juicy.

That’s slow money, kid: work, save, invest, and work again, that’s what it’s all about! It ain’t pretty
but it gets you there in the end.

One final tip, kid: I’ll say this ‘cos I like ya. It won’t save you work but it will save you time,
and it might just save your life, too: if you want to get from the Witchpoint to the station fast,
without getting your jumpdrive mass-locked by anyone, friendly or otherwise, here’s what you do. Line
up on the planet; angle up away from it by near enough ninety degrees; then hit the Torus jumpdrive
and scoot on out of the main spacelane for a few hundred klicks or so. Then, when you’ve given yourself
enough sky, pull the nose back round and come on down to the station. Chances are you won’t meet a soul,
whether you’re cruising into Ensoreus or creeping into Qudira. The spacelanes is where the action is,
where there’s help and hostility both; you get nervous, you go off-beam. Most times, you’ll come through
safe.

Huh. Anyhow. I’m a busy frog, I can’t stay here all day filling in every Jameson on what they should have
learned in the spawning pond. Gimme your ticket, kid, and I’ll stamp it flight-ready, though Giles knows I
prob’ly shouldn’t... there ya go. That’s you ready to take on the Witch. Jens help us all... don’t know
enough to keep a level bearing through a wormhole... what they send up here for us to deal with... pick up
the pieces more like...


---------------------------
*Disclaimer: 
The above text makes reference to certain Oolite eXpansion Packs (OXPs), that are not part of the core
Oolite game. The fact that certain elements from OXPs are mentioned does not necessarily mean that
these OXPs are recommended by the Oolite Team, as OXP selection and usage is subject to user personal
preferences. The OXPs mentioned in Advice for New Commanders are Rusties, Bank of the Black Monks,
Ore Processor, Communist flavour pack, Dictatorship flavour pack, Your Ad Here. All Oolite OXPs are
available for download from http://wiki.alioth.net/index.php/OXP
