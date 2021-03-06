#!/usr/bin/env perl

BEGIN { $::top_path='/Users/imel/gitdev/Kepler-Discoveries' }

=head1 Name 

gen_kepler_flc.pl - Generate folder light curves for Kepler Planets using the NASA Exoplanet Archive

=head1 Synopsis

  ./gen_kepler_flc.pl kepler-name > kepler-name.xml

This script uses the NASA Exoplanet Archive (I<http://exoplanetarchive.ipac.caltech.edu>) API to
extract the DV light curve for a given Kepler Name and generate an XML file suitable for use by 
the Kepler Discoveries table:   I<http://kepler.nasa.gov/Mission/discoveries/>

=head1 Options

=over 4

=item -q -quiet

Execute without printing to STDERR "progress/status" and planet web-page found updates

=back

=cut

use strict;
use warnings;

use Data::Dumper;

use lib "$::top_path/lib";   # use the correct path here
use Utilities qw( nw pi fmod is_number );
use XA;
use IPAC_AsciiTable;

# global to this file:  command line options

our %opt;

our $REG_KEPOI_NAME='K0*([1-9]\d*\.\d\d)';  # captures the numeric part

sub msg {
  my $out=shift();
  my $label=shift() // '';
  unless ($label=~/(FAIL)|(DIE)|(RESULT)/i) {
    return if $label=~/DEBUG/i && !$opt{debug};
    return if $opt{q};
  }
  print STDOUT sprintf('%8s: %s',$label,$out),"\n";
}

sub fail { msg shift(),'FAIL'; exit; }

sub check(&$) { 
  my $test=shift; 
  my $msg=shift() // '[ Unspecified assertion ]';
  if (&$test) { msg  $msg, 'DEBUG-OK'; return 1 }
  else        { msg  $msg, 'CHECK-NO'; return 0 }
}

sub assert(&$) { 
  my $test=shift;
  my $msg=shift;
  unless ( check { &$test } $msg ) { fail $msg } 
}

sub sort_with_first {
  my $first=shift;
  return ($first,sort { $a cmp $b } grep { $_ ne $first } @_);
}

# script functions for encoding XML data

sub load_meta {
  my $X=shift;  # reference to XA object
  my $T=shift;  # TCE parameters for the preferred planet
  my $S=shift;  # Stellar data from Cumulative KOI Table
  my @pnames=@_;
  my $first=1;  # host and 'other' data only assigned once
  my $m;
  for my $pname (@pnames) {
    my $n=$X->keplernames_planet_row($pname);
    assert { exists $n->{alt_name} } "Got Exoplanet Table Entry Name for $pname";
    msg "Keplernames Planet Row for $pname", 'DEBUG';
    my $e=$X->exoplanet_planet_row($n->{alt_name});
    msg "Exoplanet Planet Row for $n->{alt_name}", 'DEBUG';
    # load planet parameters
    for (keys %$e) { $m->{planets}{$n->{kepler_name}}{$_}=$e->{$_} }
    if ($first) {
      # load selected host parameters
      $m->{st_rad} =$S->{koi_srad};   # default, override by planet table if available
      $m->{st_teff}=$S->{koi_steff};  # default, override by planet table if available
      for (qw( pl_hostname st_rad st_teff )) { $m->{$_}=$e->{$_} if $e->{$_} }   # only works because '0' and '0.00' are not valid values
      $m->{pl_name}=$n->{kepler_name};   # preferred planet name (not necessarily $e->{pl_name}!!!
      override_meta($m->{planets}{$m->{pl_name}},$T);
      # other parameters
      $m->{date}=$n->{last_update};
      $first=0;
    }
  }
  return $m;
}
    
# the checks here assume that zero is not an acceptable value for any of these parameter values
sub override_meta {
  my $pmeta=shift;    # hash of planet-specific meta-data we are loading / overriding
  my $tcep=shift;     # hash of TCE parameters for the preferred planet
  my $fplanet=$pmeta->{pl_name};
  msg "$fplanet:  $pmeta->{pl_orbsmax} vs. $tcep->{tce_sma}", 'DEBUG';
  $pmeta->{pl_orbsmax}=$tcep->{tce_sma}           if $tcep->{tce_sma};   # AU
  msg "$fplanet:  $pmeta->{pl_trandur} vs. @{[ $tcep->{tce_duration}/24.0 ]}", 'DEBUG';
  $pmeta->{pl_trandur}=$tcep->{tce_duration}/24.0 if $tcep->{tce_duration};  # days vs. hours
  msg "$fplanet:  $pmeta->{pl_radj} vs. @{[ $tcep->{tce_prad}/11.209 ]}", 'DEBUG';
  $pmeta->{pl_radj}   =$tcep->{tce_prad}/11.209   if $tcep->{tce_prad};    # jupiter radius vs. earth radius
  msg "$fplanet:  $pmeta->{pl_orbper} vs. $tcep->{tce_period}", 'DEBUG';
  $pmeta->{pl_orbper} =$tcep->{tce_period}        if $tcep->{tce_period};         # days
}

sub wrap_xml {
  my $keyword=shift;
  my $content=shift;
  my $nl=shift() // "\n";
  return '<'.$keyword.'>'.$content.'</'.$keyword.'>'.$nl;
}

sub series_xml {
  my $time=shift;
  my $data=shift;
  my $filt=shift;
  assert { $#{$time}==$#{$data} } "Expect time and data to have same array lengths";
  my $xml='';
  for my $i (0..$#{$time}) {
    $filt->[$i]=0 unless (is_number($time->[$i]) && is_number($data->[$i]));  # delete NaNs for data & model
    $xml.=wrap_xml('pt',wrap_xml('ma',$time->[$i],'').wrap_xml('i',$data->[$i],'')) if $filt->[$i];
  }
  return $xml;
}

sub gen_xml {
  my $meta=shift;
  my $time=shift;
  my $data=shift;
  my $model=shift;
  my $filter=shift;

  my $xml;
  $xml =wrap_xml('name',              $meta->{pl_hostname});
  $xml.=wrap_xml('starRadius',        $meta->{st_rad})       if defined $meta->{st_rad};
  $xml.=wrap_xml('starTemperature',   $meta->{st_teff})      if defined $meta->{st_teff};
  $xml.=wrap_xml('featuredPlanetName',nw($meta->{pl_name}));

  my $pi2 = pi()/2.0;

  my $mpxml;
  for my $pname (sort_with_first($meta->{pl_name},keys %{$meta->{planets}})) {
    my $pxml;
    my $is_featured=($meta->{pl_name} eq $pname);
    my $pmeta=$meta->{planets}{$pname};  
    for (qw( pl_orbsmax pl_trandur pl_radj pl_orbper )) {
      unless (defined $pmeta->{$_}) { msg "No $_ parameter for planet $pname.  Skipping...", 'WARN'; return undef }
    }
    msg "Loading data for planet $pname:  ".Dumper($pmeta), 'DEBUG';
    $pxml = wrap_xml('name',                       nw($pname));
    $pxml.= wrap_xml('semimajorAxis',              $pmeta->{pl_orbsmax} || '0');
    $pxml.= wrap_xml('radius',                     $pmeta->{pl_radj}    || '0');   # JUPITER RADIUS???
    $pxml.= wrap_xml('period',                     $pmeta->{pl_orbper}  || '0');
    if ($is_featured) {
      $pxml.= wrap_xml('longitudeOfAscendingNode',   undef // $pi2);  
      $pxml.= wrap_xml('argumentOfPericenter',       undef // $pi2);
    }
    $pxml.= wrap_xml('inclination',               ($pmeta->{pl_orbincl}  ||90.0) * pi()/180.0 );  # edge-on is pi/2
    $pxml.= wrap_xml('eccentricity',               $pmeta->{pl_orbeccen} ||0.0   );  # getting null string for this from db
    if ($is_featured) {
      $pxml.= wrap_xml('transitDuration',           ($pmeta->{pl_trandur}||0.0)*24.0);       # convert from days to hours
      $pxml.= wrap_xml('meanAnomalyAtTransitMiddle', undef // 0.0);
    }
    if ($is_featured) {
      $pxml.='<!-- data for '.nw($pname).', generated '.$meta->{date}.' -->'."\n";
      $pxml.=wrap_xml('dataPoints', "\n".series_xml($time,$data, $filter));
      $pxml.=wrap_xml('curvePoints',"\n".series_xml($time,$model,$filter));
    }
    $mpxml.=wrap_xml('planet',"\n$pxml");
  }

  $xml.=wrap_xml('planets',           "\n$mpxml");

  $xml=wrap_xml('system',"\n$xml");
  return $xml;
}

=head1 DESCRIPTION

gen_kepler_flc.pl performs the following actions:

=over 4

=item 

Query the NASA Exoplanet Archive to get the following for the Kepler Name supplied on the command-line:

=over 4

=item 

Planet parameters from the "Exoplanets" Table.

=item 

Stellar parameters from the "Exoplanets" Table.

=item 

DV Light-Curve data

=back

=item 

"Fold" the Light-Curve data based on the returned planet parameters

=item

Write to STDOUT the XML file suitable for use by the Kepler Discoveries website.

=back

=cut

#############################
# The main script follows
#############################

package main;

use Data::Dumper;

use LWP::Simple;
use Getopt::Long;

GetOptions (\%opt, 'all', 'q|quiet', 'tbl=s', 'keep_tbl', 'max=i', 'debug', 'show_data');

die "Usage:  $0 ( kepler-name | -all )" unless ( scalar(@ARGV) or defined $opt{all} );

my $X=new XA;
my @r=$X->kepler_names;

my $np=scalar(@r);                      # number of planets
msg "Loaded $np confirmed planets";

# my @plist=$opt{all} ? sort { $a cmp $b } @r : ( join(' ',@ARGV) ); 

my $i_np = 0;       # counter

for my $kname ($opt{all} ? sort { $a cmp $b } @r : ( join(' ',@ARGV) )) {

  last if defined $opt{max} && (++$i_np>$opt{max});
  
  my $n=$X->keplernames_planet_row($kname);
  
  assert { defined $n->{alt_name}   } "$kname:  Got Exoplanet Table Entry Name";
  assert { defined $n->{kepoi_name} } "$kname:  Got Kepler Name:  $n->{kepoi_name}";
  
  msg "Keplernames Planet Row for $kname:";
  msg Dumper($n), 'DEBUG';
  
  my ($kepoi_number)=($n->{kepoi_name}=~/$REG_KEPOI_NAME/o);  # undef if no match
  next unless check { defined $kepoi_number && $kepoi_number=~/\d+[.]\d{2}/ }
    "$kname:  valid kepoi number from kepoi_name ($n->{kepoi_name} in Exoplanet Table)";
  
  my $e=$X->exoplanet_planet_row($n->{alt_name});
  msg "Exoplanet Planet Row for $n->{alt_name}:";
  msg Dumper($e), 'DEBUG';
  
  # this is a bit awkward, but match the hostname against all the known planets,
  # then sort them with the requested planet first in order
  
  msg "There should be $e->{pl_pnum} planets in this system";
  my @pnames=sort_with_first($kname,grep /$e->{pl_hostname}\s+[b-z]+/, @r);
  msg "Found the following:  ".join(' ',@pnames);
  
  next unless check { $n->{koi_list_flag} eq 'YES' } 
    "$kname:  have data for $n->{kepoi_name}: koi_list_flag=$n->{koi_list_flag}";
  
  my $tce_data=$X->tce_data_for_kepoi_name($n->{kepoi_name});
  msg Dumper($tce_data), 'DEBUG';
  
  next unless check { defined $tce_data and scalar(keys %$tce_data) } "$kname:  TCE data available for $n->{kepoi_name}";
  assert { scalar(keys %$tce_data)==1 } "$kname:  Should be only one TCE for $n->{kepoi_name}";
  my ($tce)=keys %$tce_data;   # should be only one!
  
  my $period=$tce_data->{$tce}{tce_period};
  my $offset=$tce_data->{$tce}{tce_time0bk};
  my $duration=$tce_data->{$tce}{tce_duration};
  
  msg "Fetching DV Time Series data for $n->{kepid} and tce $tce";
  my $dv_data=$X->dv_series($n->{kepid},$tce,$X->tce_deliv_for_kepoi_name($n->{kepoi_name}));
  next unless check { defined $dv_data } "$kname:  Couldn't extract DV series from $n->{kepid} and tce $tce";

  my $cum_stellar_data=$X->stellar_data_for_kepoi_name($n->{kepoi_name});
  msg Dumper($cum_stellar_data), 'DEBUG';
  
  next unless check { defined $cum_stellar_data and scalar(keys %$cum_stellar_data) } "$kname:  Stellar data from Cum KOI table available for $n->{kepoi_name}";
  assert { scalar(keys %$cum_stellar_data)==1 } "$kname:  Should be only one Cum KOI Table Stellar Data entry for $n->{kepoi_name}";
  my ($csd_key)=keys %$cum_stellar_data;   # should be only one!

  
  my $tempfile="$n->{kepid}_$tce.$$.tbl";
  open TEMP, ">$tempfile" or fail "Couldn't create $tempfile:  $!";
  print TEMP $dv_data, "\n";
  close TEMP;
  
  my $meta=load_meta($X,$tce_data->{$tce},$cum_stellar_data->{$csd_key},@pnames);   # gather all info, and process into meta data for XML writing
  # use TCE versions of parameters, where available
  
  my $T=new IPAC_AsciiTable $tempfile;

  my $tnc=$T->n_cols();
  my $tnr=$T->n_data_rows();
  
  msg "Read in $tnc cols and $tnr rows from $tempfile";
  
  my @time=$T->col('TIME');
  my @data  = map { $_+1.0 } $T->col('INIT_FLUX_PL');
  my @model = map { $_+1.0 } $T->col('MODEL_LC_PL');
  
  my $PI=4.0*atan2(1.0,1.0);
  
  # need to restrict range of data to +/- 1 transit duration; probably use filter array
  my @folded_time=map { $_*2.0*$PI/$period - $PI } map { fmod($_-$offset+$period/2.0,$period) } @time;
  my $phs_rad=$duration/24.0 * 2.0 * $PI / $period;
  my @time_filter=map { ($_>$phs_rad)||($_<-$phs_rad) ? 0 : 1 } @folded_time;   # only +/- transit duration from center phase
  
  # need to sort the phases
  my @sort_indices=sort { $folded_time[$a]<=>$folded_time[$b] } (0..$#folded_time);
  
  @folded_time=@folded_time[@sort_indices];
  @data       =@data[@sort_indices];
  @model      =@model[@sort_indices];
  @time_filter=@time_filter[@sort_indices];
  
  if ($opt{show_data}) {
    for my $i (0..$#folded_time) {
      print "$time_filter[$i]  $folded_time[$i] $data[$i] $model[$i]\n";
    }
  }
  my $xml_out=lc($kname);  $xml_out=~s/(\s+|-)//g; $xml_out.='.xml';
  open XML, ">$xml_out" or fail "Couldn't create $xml_out:  $!";
  print XML gen_xml($meta,\@folded_time,\@data,\@model,\@time_filter);
  close XML;
  
  msg "Wrote $xml_out for $kname", 'RESULT';
  unlink $tempfile unless $opt{keep_tbl};   # cleanup

}

###############
# End of Script
###############

=head1 TODO

Known items to be implemented and issues to be addressed.

=over 4

=item

All steps still "ToDo".

=back

=head1 CHANGES

=over 4

=item 2014-11-04

Initial script-in-prep, modified from names_table.pl script.

=back

=head1 AUTHOR

  Dr. David A. Imel, <imel@caltech.edu>
  IPAC/NExScI California Institute of Technology
  2014-11-04

=cut

