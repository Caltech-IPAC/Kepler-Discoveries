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

use Utilities qw( tw identical_arrays );

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

=cut

sub new_empty {
  my $class=shift;
  my %T;
  @T{qw( S C K H D T U N M )}=();
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
      when (/^[\\]?\s*$/) { next }  # ignore blank lines
      when (/^\\\s(.*)$/) { push @{$T->{C}}, $1 }
      when (/^\\(\S+)\s*[=]\s*(.*)$/) { $T->{K}{$1}=$2 }
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
  return $T;
}

sub new {
my $class=shift;
my $filename=shift;
return new_from_file($class,$filename) if defined $filename;
return new_empty($class);
}

sub n_cols { my $self=shift; return scalar(@{$self->{H}}) }
sub col_name { my $self=shift; return $self->{H}[shift()] }
sub n_data_rows { my $self=shift; return scalar(@{$self->{D}{$self->col_name(0)}}) }

sub row { # get full data row (specified by number)
  my $self=shift;
  my $r=shift;
  my @col_names=scalar(@_) ? @_ : @{$self->{H}};
  my @o;
  for (@col_names) { push @o, $self->{D}{$_}[$r] }
  return @o;
}

sub col {  # get full data column (specified by name)
  my $self=shift;
  my $c=shift;
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

sub write_row {
  my $self=shift;
  my $fh=shift; # file handle
  my $A=shift;  # data array
  my $d=shift;  # delimeter
  # need to verify that number of markers and number of 
  # columns line up here...
  for my $i (0..scalar(@$A)-1) {
    my $fw=$self->{M}[$i+1]-$self->{M}[$i]-1;
    print $fh sprintf("$d%${fw}s",$A->[$i]);
  }
  print $d,"\n";
}

sub write {  # write out an ascii table
  my $self=shift;
  my $fh=shift;
  for (sort { $a cmp $b } keys %{$self->{K}}) {
    print $fh '\\',$_,' = ',$self->{K}{$_},"\n";
  }
  $self->write_row($fh,$self->{H},'|');
  $self->write_row($fh,$self->{T},'|');
  $self->write_row($fh,$self->{U},'|') if defined $self->{U};
  $self->write_row($fh,$self->{N},'|') if defined $self->{N};
  for (0..$self->n_data_rows()-1) {
    $self->write_row($fh,[ $self->row($_) ],' ');
  }
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

