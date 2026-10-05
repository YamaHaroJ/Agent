#!/usr/bin/perl
use strict;
use warnings;
use DynaLoader;

my $dylib = shift @ARGV
    or die "usage: clock-nowplaying.pl /absolute/path/to/libClockNowPlaying.dylib\n";

DynaLoader::dl_load_file($dylib, 0x01)
    or die "failed to load $dylib: " . DynaLoader::dl_error() . "\n";

$SIG{TERM} = sub { exit 0 };
$SIG{INT}  = sub { exit 0 };

while (1) {
    sleep 3600;
}
