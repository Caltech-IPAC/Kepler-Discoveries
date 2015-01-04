package XA;         # Exoplanet Archive API access

=head1 Name 

XA.pm - Interface to the NASA Exoplanet Archive

=head1 Synopsis

=cut

use strict;
use warnings;

use Data::Dumper;
use LWP::Simple;

use Utilities qw( uniq );
use XAQ;  # lives in the same path as this module, so should be locatable if this module was.

=head1 Description

The XA package makes use of the XAQ class do specific queries on 
Exoplanet Archive data and return content of interest to the rest of this script.

=cut

my $WGET_URL="http://exoplanetarchive.ipac.caltech.edu/bulk_data_download/Kepler_TCE_DV_wget.bat";

# parse the result from a table "select all".  
# return is a reference to a hash of hash references, where
#   each row is referenced by the "index column" value, and
#   each row is a hash of (column_name=>column_value_for_row)

# Note:  this is not a "member function"

sub parse_table_by_index {
  my $i=shift;  # index column for table
  my $q=shift;  # query result (long string with multiple rows, including header)
  my $d=shift;  # delimiter for columns
  my $t=shift;  # tag for diagnostic messages
  my @r=split("\n",$q);
  my $c=shift @r;  # column header names
  unless (scalar(@r)) {    # missing this entry -- return ref to an empty hash and print warning to STDERR
    print STDERR "no data found:  $t by $i\n";
    return {};
  }
  my @c=split($d,$c);     # pipe-delimited columns makes this easier -- assuming no pipes in fields
  my $j=0;
  my $T={}; # hash of hashes, using values of $i for the keys
  for my $r (@r) {
    ++$j;    # diagnostic counter
    $r.=" " if $r=~/[|]$/;
    my @d=split($d,$r);  #  now have this row in columns @d (names are in @c)
    die "number of column names != number of values (@{[ scalar(@c) ]} != @{[ scalar(@d)]}) on row $j (row 0 is headers) for $t\n"
      ."Headers:\n".Dumper(@c)."\nData:\n".Dumper(@d)."\nSource:\n".Dumper($q)
	unless scalar(@c)==scalar(@d); # columns of data returned had better match number of column names, or quit.
    my %h;
    for (0..$#c) { $h{$c[$_]}=$d[$_] }  # fill the hash
    die "index $i not found on row $j for $t" unless exists $h{$i};
    die "index $i value ($h{$i}) is not unique at row $j for $t\n-->$r<--\n".Dumper($T) if exists $T->{$h{$i}};
    $T->{$h{$i}}=\%h;
  }
  return $T;
}

# helper function for the constructor which figures out which delivery to select for the Kepler Stellar Table kepids

sub latest_stellar_delivery {
  my $x=new XAQ;
  my $targ_col='st_delivname';
  my $date_col='st_vet_date_str';
  my $r=parse_table_by_index($targ_col, $x->select_distinct_col($targ_col,$date_col)->keplerstellar, $x->delim(), 'Kepler Stellar Latest Delivery');
  my @l=sort { $r->{$b}{$date_col} cmp $r->{$a}{$date_col} } keys %$r;
  my $latest=shift @l;
  print STDERR "Using delivery $latest for Kepler Stellar Table\n";
  return $latest;
}

sub dv_data_wgets {
  my $url=shift;
  my $bat=get($url);
  die "Couldn't get wget bat file from $url" unless $bat;
  my $result;
  for my $line (split("\n",$bat)) {
    next unless $line=~/^wget/;
    my @F=split(' ',$line);
    my $file_url=$F[3];  $file_url=~s/[']//g;
    my ($kepid,$tce)=($file_url=~/kplr(\d{9}).+?tce_(\d{2})/);
    my $key=$kepid.'_'.$tce;
    $result->{$key}=$file_url;
  }
  return $result;
}
  
# get all tables up front and parse into useful hashes
sub new { 
  my $class=shift; 
  my $self={};
  my $x;  # have to get a "clean" XAQ object for each call
  $x=new XAQ; $self->{N}=parse_table_by_index('kepler_name',$x->select_all()->keplernames,   $x->delim(),'Kepler Names');  
  $x=new XAQ; $self->{X}=parse_table_by_index('pl_name',    $x->select_all()->exoplanets,    $x->delim(),'Confirmed Exoplanets'); 
  $self->{W}=dv_data_wgets($WGET_URL);
  return bless $self, $class;
}

# selected TCE data for a particular kepid from the latest TCE table
sub tce_data_for_kepoi_name {
  my $self=shift;
  my $kepoi_name=shift;
  my $x=new XAQ;
  my @col=qw( kepoi_name kepid koi_tce_plnt_num );
  $x->select_col(@col)->equals_str('kepoi_name',$kepoi_name);
  my $r=parse_table_by_index($col[0], $x->q1_q16_koi(), $x->delim(), "Kepler KOI for $kepoi_name");
  return undef unless defined $r->{$kepoi_name};
  my $kepid=$r->{$kepoi_name}{kepid};
  my $tce  =$r->{$kepoi_name}{koi_tce_plnt_num};
  $x=new XAQ;
  @col=qw( tce_plnt_num tce_period tce_time0bk tce_duration rowupdate );
  $x->select_col(@col)->add_where("kepid=$kepid")->add_where("tce_plnt_num=$tce");
  $r=parse_table_by_index($col[0], $x->q1_q16_tce(), $x->delim(), "Kepler TCE for $kepid");
  return $r;
}

# Short-cut accessors for table rows (returned as hashes of col_name==>row_value)
# Lookup to tables is for the following column names:
#     exoplanets:   pl_name
#     keplernames:  kepler_name
# An improvement would be to check for existence of the lookup key value and 
# throw an error if not found.

sub kepler_names      { my $self=shift; return keys %{$self->{N}} }
sub kepler_stars      { my $self=shift; return uniq map { $self->{N}{$_}{kepid} } keys %{$self->{N}} }
sub kepler_multiples  { 
  my $self=shift; 
  return map { $self->{X}{$_}{pl_hostname} } grep { ($self->{X}{$_}{pl_kepflag}==1) && ($self->{X}{$_}{pl_pnum}>1) } keys %{$self->{X}};
}

sub exoplanet_planet_row   { my $self=shift; my $pname=shift; return $self->{X}{$pname} }
sub keplernames_planet_row { my $self=shift; my $kname=shift; return $self->{N}{$kname} }

sub dv_series { 
  my $self=shift; 
  my $kepid=shift; 
  my $tce=shift; 
  my $key=sprintf("%09d",$kepid).'_'.sprintf("%02d",$tce);
#  print STDERR "try to get a dv_series for $kepid and planet $tce\n";
  return undef unless defined $self->{W}{$key};
#  print STDERR "get using $self->{W}{$key}\n";
  return get($self->{W}{$key});
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
