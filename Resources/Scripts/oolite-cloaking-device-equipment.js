this.name = "Cloaking Device";

this.activated = function()
{
	player.ship.isCloaked = !player.ship.isCloaked;
}