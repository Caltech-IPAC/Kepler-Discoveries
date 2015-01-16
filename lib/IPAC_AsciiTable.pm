package IPAC_AsciiTable;

=head1 Name 

IPAC_AsciiTable.pm - Read and write IPAC ASCII format Tables

=head1 Synopsis

=cut

use strict;
use warnings;
use feature 'switch';
no if $] >= 5.017011, warnings => qw( experimental::smartmatch );

use Data::Dumper;
use POSIX ();

use Utilities qw( tw identical_arrays is_numeric_only );

# non-member functions

sub marker_capture {
  local $_=shift;
  my $m=shift() || '|';  # optionally change column marker character
  my @o;
  for (my $i=0; $i<length($_); $i++) { push @o,$i if substr($_,$i,1) eq $m }
  return @o;
}

sub column_capture {
  my $s=shift; # string from which to extract columns
  my @m=@_;    # column marker index numbers
  my @r;       # results to be returned
  for (my $i=0; $i<scalar(@m)-1; $i++) { push @r, substr($s,$m[$i]+1,$m[$i+1]-$m[$i]-1) }
  return @r;
}

=head2 round_to_length design notes

  round_to_length accepts a number and a maximum field width,
  and tries to find the best precision way to print the number
  while enforcing the field width constraint.  

  $x is guaranteed to be in a numeric format, exponential or decimal
  $l is the field width allowed for representing $x
  
  If the field width is enough to fit the string representation of the number,
  then that representation is returned.  (Not padded.)  The number
  will be rounded via the sprintf function, so it's just a matter
  of determining whether to use floating-point or exponential 
  notation, and how many decimal places to print.  Note that the
  %g field specifier of printf won't enforce the field width constraint.

    Examples:
        -134.7892  -- one char for '-', three chars for whole portion,
                      one char for '.', so # decimal places is field width - 5.
                      Note that the minimum field width is 3 chars for
                      non-negative numbers, and 4 chars for negative numbers.
        -1.2e-05   -- one char for '-' on number, four chars for exponent,
                      one char for whole part of mantissa,
                      one for '.', so # decimal places is field width - 7
                      Note that the minimum field width is 5 chars for
                      non-negative numbers, and 6 chars for negative numbers.

         Use scientific notation if the field width is less than the non-decimal
         part of the number (whole-portion for non-negative, whole-portion+1 for negative),
         and when the precision of scientific notation exceeds that of floating point notation
         for fractional numbers.  This requires a field width of 4 for non-negative numbers,
         and 5 for negative numbers:

                Field width of 5:
                     0.011111: 0.011 vs 1e-02  -- floating point is better
                     0.001111: 0.001 vs 1e-03  -- equal precision
                     0.000111: 0.000 vs 1e-04  -- exponential notation is better
                Field width of 6:
                     0.001111: 0.0011 vs 1.e-03  -- floating point is better
                     0.000111: 0.0001 vs 1.e-04  -- equal precision
                     0.000011: 0.0000 vs 1.e-05  -- exponential notation is better
                Field width of 7:
                     0.001111: 0.00111 vs 1.1e-03  -- floating point is better
                     0.000111: 0.00011 vs 1.1e-04  -- equal precision
                     0.000011: 0.00001 vs 1.1e-05  -- exponential notation is better
                Field width of 8:
                     0.00011111: 0.000111 vs 1.11e-04  -- equal precision
                     0.00001111: 0.000011 vs 1.11e-05  -- exponential notation is better

          Transition points:  use exponential notation in these abs(x)<1 cases:
                     x>0, abs(x)<10^-4 and field width >= 6:  decimals = field width - 6
                     x>0, abs(x)<10^-3 and field width == 5:  decimals = 0
                     x<0, abs(x)<10^-3 and field width == 6:  decimals = 0
                     x<0, abs(x)<10^-4 and field width >= 7:  decimals = field width - 7

                     x>0, abs(x)>1, field width < length(int(x)):    decimals = field width - 6
                     x<0, abs(x)>1, field width < length(int(x))+1:  decimals = field width - 7

           Otherwise, use floating point notation, in which case:  
                     x>0:  decimals = field width - length(int(x)) - 1
                     x<0:  decimals = field width - length(int(x)) - 2
                     
           '#' cases:
                     x>0:  field width < lenth(int(x))    and field width < 5
                     x<0:  field width < length(int(x))+1 and field width < 6

=cut

sub round_to_length {
  my $x=shift;
  my $l=shift;
  return $x if length($x)<=$l;
  return '' if $l<1;    # shouldn't really allow this!
  return sprintf('%'.$l.'.'.($l>1?$l-2:0).'f',$x) if $x==0;
  my $wnl=length(int(abs($x)));
  my $neg= $x<0 ? 1 : 0;
  my $sci_prec=undef;
  return '#'x$l if ($l<$wnl+$neg) && ($l<5+$neg);  # can't do sci notation or floating point
  if    ( ((abs($x)<1e-4) && ($l>=6+$neg)) || ((abs($x)>1) && ($l<$wnl+$neg)) )  { $sci_prec=$l-6-$neg }
  elsif ( (abs($x)<1e-3) && ($l==5+$neg) )                                       { $sci_prec=0 }
  return sprintf('%'.$l.'.'.($sci_prec<0?0:$sci_prec).'e',$x) if defined $sci_prec;
  my $flt_prec=$l-$wnl-1-$neg;
  return sprintf('%'.$l.'.'.($flt_prec<0?0:$flt_prec).'f',$x);
}

sub pad_to_length {
  my $x=shift;
  my $l=shift;
  return $x if length($x)>=$l;
  return ' 'x($l-length($x)).$x;
}

sub _output_row {
  my $A=shift;  # data array
  my $M=shift;  # array of delimiter positions
  my $d=shift;  # delimiter character
  my $out="";
  # need to verify that number of markers and number of 
  # columns line up here...
  for my $i (0..$#{$M}-1) {
    my $fw=$M->[$i+1]-$M->[$i]-1;
    my $datum=(defined $A->[$i])
      ? (is_numeric_only($A->[$i]) ? round_to_length($A->[$i],$fw) : substr($A->[$i],0,$fw)) 
      : '';
    $out.=$d.pad_to_length($datum,$fw);  # need to truncate $A->[$i] if too long?
  }
  return $out.$d;
}

=head1 Design Notes

  S Original source
  C comments 
  K key/value pairs
  H headings for each column
  D Data (by labeled columns)
  T type for each column
  U units for each column
  N null values for each column
  M Marker positions for columns
  I Map of column name -> column number

=cut

sub new_empty {
  my $class=shift;
  my %T;
  for (qw( H T U M N S C )) { $T{$_}=[] }  # init array elements
  for (qw( D K I )        ) { $T{$_}={} }  # init hash  elements
  return bless \%T, $class;
}

# modify this to do "open_file" and "read_line" calls
# so that we don't have to read in the entire file at
# once if it's too large to do so?

sub new_from_file {
  my $class=shift;
  my $file=shift;
  my $T=new_empty($class,$file);
  # read file here
  my $fh;
  open($fh,'<',$file) or die "Couldn't open $file for read:  $!";
  my @m=qw( M H T U N );  # keep track of order of column info
  my %c;  for (@m) { $c{$_}=0 }
  while (<$fh>) {
    chomp;
    push @{$T->{S}}, $_;
    # need validation on the file contents -- correct file formats are assumed below
    for ($_) {
      when (/^[\\]?\s*$/)                            { next }  # ignore blank lines
      when (/^\\\s(.*)$/)                            { push @{$T->{C}}, $1 }
      when (/^\\(\S+)\s*[=]\s*(["']?)(.*?)(\2)\s*$/) { $T->{K}{$1}=$3 }  # remove matching quotes, if any
      when (/^[|]/) { 
	my @cm=marker_capture($_,'|');
	if ($c{M}) { 
	  unless (identical_arrays(\@cm,\@{$T->{M}})) {
	    print Dumper($T),"\n";
	    die "inconsistent column markers; line is:\n$_\n";
	  }
	} else { $T->{M}=\@cm; $c{M}=1 }
	my @c=map { tw($_) } column_capture($_,@{$T->{M}});
	for my $m (@m) {
	  next if $c{$m};  # already have this column info
	  $T->{$m}=\@c;    # capture new column info
	  $c{$m}=1;        # mark that we have this column info
	  last;            # only one kind of info per row
	}
      }
      default {  # assume a data line, and sort into columns
	unless ($c{H} && $c{T}) {
	  print Dumper($T),"\n";
	  die "Apparent data line prior to defining mandatory headers:\n$_\n" 
	}
	my @c=map { tw($_) } column_capture($_,@{$T->{M}});
	for my $h (@{$T->{H}}) { push @{$T->{D}{$h}}, shift(@c) }
      }
    }
  }
  for (0..$#{$T->{H}}) { $T->{I}{$T->{H}[$_]}=$_ }
  return $T;
}

sub new {
my $class=shift;
my $filename=shift;
return new_from_file($class,$filename) if defined $filename;
return new_empty($class);
}

sub parm_list   { my $self=shift; return keys %{$self->{K}} }
sub parm_value  { my $self=shift; return $self->{K}{$_[0]} // undef }

sub n_cols      { my $self=shift; return scalar(@{$self->{H}}) }
sub col_name    { my $self=shift; return $_[0] < $self->n_cols() ? $self->{H}[$_[0]] : undef }
sub col_number  { my $self=shift; return exists $self->{I}{$_[0]} ? $self->{I}{$_[0]} : undef }
sub n_data_rows { my $self=shift; return $self->n_cols() ? scalar(@{$self->{D}{$self->col_name(0)}}) : 0 }

sub row { # get full data row (specified by number)
  my $self=shift;
  my $r=shift;
  return undef unless $r<$self->n_data_rows();
  my @col_names=scalar(@_) ? @_ : @{$self->{H}};
  my @o;
  for (@col_names) { push @o, $self->{D}{$_}[$r] }
  return @o;
}

sub col {  # get full data column (specified by name)
  my $self=shift;
  my $c=shift;
  return undef unless exists $self->{D}{$c};
  return @{$self->{D}{$c}};
}

sub extract {  # get data sub-table:  all rows for a specified list of column names
  my $self=shift;
  my %t;
  for (@_) { push @{$t{$_}}, $self->col($_) }
  return \%t;
}

sub add_col { # add a new column of data
  my $self=shift;
  my ($h,$t,$u,$n,$d)=@_;
  $self->{D}{$h}=();
  for (@$d) { push @{$self->{D}{$h}}, $_ }
  push @{$self->{H}},$h;
  push @{$self->{T}},$t;
  push @{$self->{U}},$u if defined $u;
  push @{$self->{N}},$n if defined $n;
  # get new column width from data values
  my $max_col_length=max( map { 1+length($_) } (@$d,$h,$t,(defined $u ? $u : ''),(defined $n ? $n : '')) );
  push @{$self->{M}},$max_col_length+$self->{M}[-1];
}

sub output_row {
  my $self=shift;
  my $A=shift;  # data array
  my $d=shift;  # delimiter
  return _output_row($A,$self->{M},$d);
}

=head2 set_marker_array

  scans through each column of data to find maximum extent of the column data,
  does a "max" function on that length and the length of the headers to
  report a max length for the column, and constructs an array of marker positions
  from those lengths.

=cut

sub set_marker_array {
  my $self=shift;
  my @max_col_length;
  for my $c (0..$self->n_cols()-1) {
    my $cn=$self->col_name($c);
    push @max_col_length,max( map { length($_) } ($self->col($cn),$self->{H}[$c],$self->{T}[$c],$self->{U}[$c],$self->{N}[$c]) );
  }
  my @m=( 0 );
  for (@max_col_length) { push @m, $m[$#m]+$_+1 }
  $self->{M}=\@m;
}

sub write {  # write out an ascii table to a filehandle
  my $self=shift;
  my $fh=shift;
  $self->set_marker_array();
  for (sort { $a cmp $b } keys %{$self->{K}}) {
    print $fh '\\',$_,' = ',$self->{K}{$_},"\n";
  }
  for (qw( H T U N )) {
    print $fh $self->output_row($self->{$_},'|'),"\n";
  }
  for (0..$self->n_data_rows()-1) {
    print $fh $self->output_row([ $self->row($_) ],' '),"\n";
  }
}

sub write_to_file {
  my $self=shift;
  my $file=shift;
  open(my $fh, '>', $file ) or die "Couldn't create $file:  $!";
  $self->write($fh);
  close $fh;
}

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

