#!/usr/bin/perl

use strict;
use warnings;

my $begin = 0;

my @accum = "";

print ("{\n\n");

print ('	"interstellar space" =
	{
		sky_color_1 = (0, 1, 0.5);
		sky_color_2 = (0, 1, 0);
		nebula_color_1 = (0, 1, 0.5);
		nebula_color_2 = (0, 1, 0);
		sky_n_stars = 2048;
		sky_n_blurs = 256;
	};

	"universal" = 
	{
		sky_color_1 = (0.75,0.8,1);
		sky_color_2 = (1.0,0.85,0.6);
		stations_require_docking_clearance = no;
	};

	// Uncomment the desired behaviour for galactic hyperspace exit. Fixed coordinates will put the arrival
	// of an intergalactic jump on map coordinates specified by the key galactic_hyperspace_fixed_coords.
	"galactic_hyperspace_behaviour" = 	"BEHAVIOUR_STANDARD";
						//"BEHAVIOUR_ALL_SYSTEMS_REACHABLE";
						//"BEHAVIOUR_FIXED_COORDINATES";
						
	// When using BEHAVIOUR_FIXED_COORDINATES, the key below is used to specify the
	// actual fixed coordinates for the intergalactic jump.
	"galactic_hyperspace_fixed_coords" = 	"96 96";
	
	hyperspace_tunnel_color_1 = (1.0, 1.0, 1.0, 0.7);		// R, G, B, A values 0.0 to 1.0
	
	//hyperspace_tunnel_color_1 = (1.0, 0.0, 0.0, 0.5);		// fallback value, same as docking tunnel
	//hyperspace_tunnel_color_2 = (0.0, 0.0, 1.0, 0.25);	// fallback value, same as docking tunnel
	
	/* This setting controls the minimum charge level of the energy banks
	   before the shields start charging. It\'s taken as a percentage value
	   from 0.0 (0%) to 1.0 (100%).  If the energy banks are less than this,
       energy is first used to charge the banks, and only then the shields.
	   Default: 0.0
	*/
	//shield_charge_energybank_threshold = 0.75;

');

while (<>) {
	chomp;
	if (/PLANETINFO LOGGING/) {
		if ($begin == 0) {
			$begin = 1;
		}
		s/.*PLANETINFO LOGGING]: //;
		print ("\t".'"'.$_.'" = {'."\n");
		@accum = ();
	} elsif ($begin && /planetinfo.record/) {
		s/.*planetinfo.record]: //;
		my $record = "";
		my $line = $_;
		$line =~/([a-z_ ]+) = (.*)/;
		my $key = $1;
		my $val = $2;
		$val =~s/;$//;
		if ($key =~/color/) {
			$val =~s/,//g;
		}
		$key =~s/planet zpos/planet_distance/;
		$key =~s/seed/random_seed/;
		$record .= ("\t\t".$key." = ");
		if ($val !~/"/ && $val =~/[^0-9.]/) {
			$record .= ('"'.$val.'"');
		} else {
			$record .= ($val);
		}
		$record .= (";\n");
		push(@accum,$record);
	} elsif ($begin && /PLANETINFO OVER/) {
		push(@accum,"\t\tsky_n_stars = ".(5000+int(rand(5000))).";\n");
		push(@accum,"\t\tsky_n_blurs = ".(40+int(rand(160))).";\n");
		@accum = sort(@accum);
		print (join("",@accum));
		print ("\t};\n\n");
		$begin = 0;
	}
}
print ("\n}\n");
