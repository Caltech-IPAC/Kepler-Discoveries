package Utilities;

use strict;

=head1 Name 

Utilities.pm - Global functions of general use

=head1 Synopsis

=cut

use parent qw( Exporter );
our @EXPORT_OK = qw( pi tw nw uniq max identical_arrays fmod is_number
		     deg_to_hhmmss deg_to_ddmmss dec_str ra_str );

my $PI = 4.0*atan2(1.0,1.0);

sub pi { return $PI }
sub tw { local $_=shift; s/^\s+//; s/\s+$//; return $_ }  # remove leading and trailing white-space
sub nw { local $_=shift; s/\s+//g;           return $_ }  # remove all white-space

sub uniq { keys %{ { map { $_ => 1 } @_ } } }

sub max {
  my $a = (ref $_[0]) ? $_[0] : [ @_ ];
  die "Argument is not an array or arrayref" unless ref $a eq 'ARRAY';
  my $m=shift @$a;
  for (@$a) { $m=($_>$m) ? $_ : $m }
  return $m;
}

sub identical_arrays(++) {
  my $a=shift;
  my $b=shift;
  die "First argument is not an array or arrayref" unless ref $a eq 'ARRAY';
  die "Second argument is not an array or arrayref" unless ref $b eq 'ARRAY';
  return 0 unless scalar(@$a)==scalar(@$b);
  for (my $i=0; $i<scalar(@$a); $i++) { return 0 unless $a->[$i]==$b->[$i] }
  return 1;
}

sub fmod {      # floating point version of modulo function
  my $x=shift;         # value to fold
  my $f=abs(shift());  # fold-interval (negative values treated same as positive)
  if ($x<0) { return fmod( int(2-$x/$f)*$f+$x, $f ) }  # handles edge cases carefully
  return $x-int($x/$f)*$f;
}

# convert from one decimal coordinate format to HHMMSS for RA and DEC

# deg_to_hhmmss:  result is forced to be between 0 and 24 hours
sub deg_to_hhmmss {
  my $ra=fmod(shift(),360.0);  $ra/=15.0;
  my $ra_hh=int($ra);
  my $ra_mins=($ra-$ra_hh)*60.0;
  my $ra_mm=int($ra_mins);
  my $ra_secs=($ra_mins-$ra_mm)*60.0;
  return ($ra_hh,$ra_mm,$ra_secs);
}

# result allowed to be negative, which means
# that the largest non-zero term must carry the sign.  I.e.,
#   -1.00 deg = -1   0   0
#   -0.50 deg =  0 -30   0
#   -0.01 deg =  0   0 -36

sub deg_to_ddmmss {
  my $dec=shift;                            
  my $dec_deg=int($dec);                    
  my $dec_mins=abs($dec-$dec_deg)*60.0;     
  my $dec_mm=int($dec_mins);                
  my $dec_secs=abs($dec_mins-$dec_mm)*60.0; 
  # fix the signs if necessary
  if ($dec<0) {                             
    if ($dec_deg==0) {                      
      $dec_mm*=-1;                          
      if ($dec_mm==0) {                     
	$dec_secs*=-1;                      
      }
    }
  }
  return ($dec_deg,$dec_mm,$dec_secs);
}

# may need to handle negative values of DEC.  (But not RA.)

sub dec_str { 
  my $dec_deg=shift;
  my ($dd,$mm,$ss)=map { abs($_) } deg_to_ddmmss($dec_deg);
  if ($dec_deg<0) { return sprintf("-%d %02d %5.2f",$dd,$mm,$ss) } 
  else            { return sprintf("%+d %02d %5.2f",$dd,$mm,$ss) }
}

sub ra_str  { return sprintf("%+d %02d %5.2f",deg_to_hhmmss(shift())) }

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

