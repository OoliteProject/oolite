# Planetinfo creator

* `1.80-planetinfo-data-extract.log` is the (relevant) log lines from
  running 26c815b3 in OO_DUMP_PLANETINFO mode for every system.
* `radii.txt` separate file containing planet radii in km because I forgot
  to include that value in the log dump and don't want to spend four
  hours regenerating it
* `seeds.txt` separate file containing system seed strings, same reason
* `planetlog.pl` is a tool to convert this into a planetinfo.plist file

The log is saved here because even with the debugging tools enabled by
OO_DUMP_PLANETINFO it still takes about four hours to generate it.

If we want to change the generation rules a bit later (e.g. modify
distance ratios, or planet colour schemes) then it may be easier to
modify planetlog.pl and regenerate.

