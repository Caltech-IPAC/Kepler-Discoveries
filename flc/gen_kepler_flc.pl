#!/usr/bin/env perl

BEGIN { $::top_path='/Users/imel/dev/Kepler-Discoveries' }

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

# use Time::Piece;
use Data::Dumper;

use lib "$::top_path/lib";   # use the correct path here
use Utilities;
use XA;
use IPAC_AsciiTable;

# script functions for encoding XML data

sub load_meta {
  my $n=shift;
  my $e=shift;

  my $m;
  $m->{planets}{$n->{kepler_name}}{semimajoraxis}=$e->{plorbsmax};
  $m->{planets}{$n->{kepler_name}}{radius}       =$e->{pl_radj};    # JUPITER RADIUS!
  $m->{planets}{$n->{kepler_name}}{period}       =$e->{pl_orbper};
  $m->{planets}{$n->{kepler_name}}{inclination}  =$e->{pl_orbincl};
  $m->{planets}{$n->{kepler_name}}{eccentricity} =$e->{pl_orbeccen};

  $m->{pl_hostname}=$e->{pl_hostname};
  $m->{st_rad} =    $e->{st_rad};
  $m->{st_teff}=    $e->{st_teff};
  $m->{pl_name}=    $e->{pl_name};
  $m->{date}=       $n->{last_update};

  return $m;
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
  print STDERR "WARNING***>mis-matched series data:  " unless $#{$time}==$#{$data};
  my $xml;
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
  $xml.=wrap_xml('featuredPlanetName',$meta->{pl_name});

  my $mpxml;
  for my $pname (keys %{$meta->{planets}}) {
    my $pxml;
    my $pmeta=$meta->{planets}{$pname};
    $pxml = wrap_xml('name',         $pname);
    $pxml.= wrap_xml('semimajorAxis',$pmeta->{semimajoraxis}) if defined $pmeta->{semimajoraxis};
    $pxml.= wrap_xml('radius',       $pmeta->{radius})        if defined $pmeta->{radius};
    $pxml.= wrap_xml('period',       $pmeta->{period})        if defined $pmeta->{period};
    $pxml.= wrap_xml('inclination',  $pmeta->{inclination})   if defined $pmeta->{inclination};
    $pxml.= wrap_xml('eccentricity', $pmeta->{eccentricity})  if defined $pmeta->{eccentricity}; 
    if ($meta->{pl_name}=~/$pname/) {
      $pxml.='<!-- data for '.$pname.', generated '.$meta->{date}.' -->'."\n";
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
my %opt;
GetOptions (\%opt, 'q|quiet', 'tbl=s', 'keep_tbl', 'max=i');

print STDERR "perldoc $0 for help.\n" unless $opt{q};

die "Usage:  $0 kepler-name" unless scalar(@ARGV);

my $kname;

$kname=join(' ',@ARGV);

print STDERR "Loading all Exoplanet Archive Tables\n" unless $opt{q};

my $X=new XA;
my @r=$X->kepler_names;

my $np=scalar(@r);                      # number of planets

my $i_np = 0;       # counter

print STDERR "Loaded $np confirmed planets\n" unless $opt{q};

# for $kname (sort { $a cmp $b } @r) {

  last if defined $opt{max} && (++$i_np>$opt{max});

  my $n=$X->keplernames_planet_row($kname);
  die "No Exoplanet Table Entry Name!\n" unless $n->{alt_name};
  print STDERR "Keplernames Planet Row for $kname:\n" unless $opt{q};
#  print STDERR Dumper($n) unless $opt{q};
  
  my $e=$X->exoplanet_planet_row($n->{alt_name});
  print STDERR "Exoplanet Planet Row for $n->{alt_name}:\n" unless $opt{q};
#  print STDERR Dumper($e) unless $opt{q};
  
  my ($kepoi_number)=($n->{kepoi_name}=~/K0*([1-9]\d*\.\d\d)/);  # undef if no match
  
  if ($n->{koi_list_flag} cmp 'YES') {  # if koi_list_flag is false, then no data
    print STDERR "No DV data for $n->{kepoi_name}; koi_list_flag=$n->{koi_list_flag}\n";
    next;
  } 
  
  my $tce_data=$X->tce_data_for_kepoi_name($n->{kepoi_name});
  print STDERR Dumper($tce_data) unless $opt{q};

  unless (defined $tce_data and scalar(keys %$tce_data)) {
    print STDERR "No TCE data available for $n->{kepoi_name}\n";
    next;
  }

  my ($tce)=keys %$tce_data;   # should be only one!

  my $period=$tce_data->{$tce}{tce_period};
  my $offset=$tce_data->{$tce}{tce_time0bk};
  my $duration=$tce_data->{$tce}{tce_duration};

  print STDERR "Fetching DV Time Series data for $n->{kepid} and tce $tce\n";
  my $dv_data=$X->dv_series($n->{kepid},$tce);
  unless (defined $dv_data) {
    print STDERR "***>Couldn't extract DV series from $n->{kepid} and tce $tce";
    next;
  }

  my $tempfile="$n->{kepid}_$tce.$$.tbl";
  open TEMP, ">$tempfile" or die "Couldn't create $tempfile";
  print TEMP $dv_data, "\n";
  close TEMP;
  
  my $meta=load_meta($n,$e);   # gather all info, and process into meta data for XML writing

  my $T=new IPAC_AsciiTable $tempfile;
  
  my $tnc=$T->n_cols();
  my $tnr=$T->n_data_rows();
  
  print STDERR "Read in $tnc cols and $tnr rows from $tempfile\n";

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

  @folded_time=remap @folded_time, @sort_indices;
  @data=remap @data, @sort_indices;
  @model=remap @model, @sort_indices;
  @time_filter=remap @time_filter, @sort_indices;

  my $xml_out=lc($kname);  $xml_out=~s/(\s+|-)//g; $xml_out.='.xml';
  open XML, ">$xml_out" or die "Couldn't create $xml_out";
  print XML gen_xml($meta,\@folded_time,\@data,\@model,\@time_filter);
  close XML;

  print STDERR "Wrote $xml_out for $kname\n" unless $opt{q};
  unlink $tempfile unless $opt{keep_tbl};   # cleanup

# }

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

