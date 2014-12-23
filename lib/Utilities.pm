package main;

=head1 Name 

Utilities.pm - Global functions of general use

=head1 Synopsis

=cut

use strict;

use Time::Piece;
use Data::Dumper;

$::M_PI = 4.0*atan2(1.0,1.0);

sub tw { local $_=shift; s/^\s+//; s/\s+$//; return $_ }  # remove leading and trailing white-space
sub nw { local $_=shift; s/\s+//g;           return $_ }  # remove all white-space

sub uniq  { keys %{ { map { $_ => 1 } @_ } } }

sub remap(\@\@) {
  my $a=shift;
  my $m=shift;
  die "remap of incompatible arrays:  @{[ scalar(@$a) ]} vs @{[ scalar(@$m) ]}" 
    unless scalar(@$a)==scalar(@$m);
  return map { $a->[$_] } @$m;
}

sub today { return Time::Piece->new->strftime('%Y/%m/%d') }
sub now   { return localtime() }

sub fmod {      # floating point version of modulo function
  my $x=shift;  # value to fold
  my $f=shift;  # fold-interval
  if ($x<0) { return fmod( int(2-$x/$f)*$f+$x, $f ) }  # handles edge cases carefully
  return $x-int($x/$f)*$f;
}

# convert from one decimal coordinate format to HHMMSS for RA and DEC

sub ra_str {
  my $ra=shift;  $ra/=15.0;
  my $ra_hh=int($ra);
  my $ra_mins=($ra-$ra_hh)*60.0;
  my $ra_mm=int($ra_mins);
  my $ra_secs=($ra_mins-$ra_mm)*60.0;
  return sprintf("%+02d %02d %5.2f",$ra_hh,$ra_mm,$ra_secs);
}

sub dec_str {
  my $dec=shift; 
  my $dec_deg=int($dec);
  my $dec_mins=($dec-$dec_deg)*60.0;
  my $dec_mm=int($dec_mins);
  my $dec_secs=($dec_mins-$dec_mm)*60.0;
  return sprintf("%+02d %02d %5.2f",$dec_deg,$dec_mm,$dec_secs);
}

sub is_number { my $x=shift; return $x=~/\d/ }

1;

=head1 License

Copyright (c) 2014, California Institute of Technology
All rights reserved. Based on research funded by NASA.

Redistribution and use in source and binary forms, with or without modification, 
are permitted provided that the following conditions are met:

   * Redistributions of source code must retain the above copyright notice, 
     this list of conditions and the following disclaimer.

   * Redistributions in binary form must reproduce the above copyright notice, 
     this list of conditions and the following disclaimer in the documentation 
     and/or other materials provided with the distribution.

   * Neither the name of the California Institute of Technology (Caltech) nor the names 
     of its contributors may be used to endorse or promote products derived from this 
     software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, 
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, 
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, 
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=head1 Auther and Version

  Version 1.1
  Dr. David A. Imel, <imel@caltech.edu>

=cut

