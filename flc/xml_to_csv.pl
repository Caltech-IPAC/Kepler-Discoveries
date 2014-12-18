#!/usr/bin/perl -w

use strict;

my $xml=shift @ARGV;

open XML, "<$xml" or die "Couldn't open $xml for reading";
my (@time, @data, @model);
my $dp=0;
my $cp=0;
while (<XML>) {
  if (m{[<]    dataPoints[>]}x) { $dp=1; next }
  if (m{[<][/] dataPoints[>]}x) { $dp=0; next }
  if (m{[<]   curvePoints[>]}x) { $cp=1; next }
  if (m{[<][/]curvePoints[>]}x) { $cp=0; next }
  s/[<].+?[>]/ /g;
  my @F=split(' ',$_);
  if ($dp) { push @data,  $F[1]; push @time, $F[0]; next }
  if ($cp) { push @model, $F[1]; print STDERR "Warning***>$F[0]!=$time[$#model]\n" unless $F[0]==$time[$#model]; next }
}

my $datfile=$xml;  $datfile=~s/\.xml/.dat/;

open FILE, ">$datfile" or die "Couldn't create $datfile";
for my $i (0..$#time) {
  print FILE $time[$i],' ',$data[$i],' ',$model[$i],"\n";
}
close FILE;

my $gnufile=$xml;  $gnufile=~s/\.xml/.gnu/;
my $psfile =$xml;  $psfile =~s/\.xml/.ps/;
open FILE, ">$gnufile" or die "Couldn't create $gnufile";
print FILE "set terminal postscript\n";
print FILE 'set output "'.$psfile.'"'."\n";
print FILE 'plot "'.$datfile.'"'." using 1:2 title 'data $datfile', ".'"'.$datfile.'"'." using 1:3 title 'model $datfile'\n";
close FILE;
