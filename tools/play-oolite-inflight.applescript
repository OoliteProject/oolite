tell application "iTunes"
	if playlist "Oolite-Inflight" exists then
		play playlist "Oolite-Inflight"
	else
		set newalias to location of some track of playlist 1
		set newlist to make new playlist
		set name of newlist to "Oolite-Inflight"
		set song repeat of newlist to all
		set shuffle of newlist to true
		add newalias to newlist
		play newlist
	end if
end tell