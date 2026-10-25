/*
	A legacy ship script. In SpiderMonkey 1.8.5 a ship script's top-level var
	was shared by every ship using the script, while bare names resolved
	through each ship's own script object.
*/

this.name = "oolite-test-compat-ship";

var sharedCount = 0;

this.shipSpawned = function ()
{
	this.$tag = "unset";
};

this.$bump = function ()
{
	sharedCount++;
	return sharedCount;
};

this.$myTag = function ()
{
	return $tag;
};
