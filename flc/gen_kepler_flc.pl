#!/usr/bin/perl -w

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
use feature 'switch';
no warnings 'experimental::smartmatch';

use Time::Piece;
use Data::Dumper;

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

sub is_number { my $x=shift; return $x=~/\d/ }

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

#################################################
# The XAQ package is used to build URL-based
# queries to the Exoplanet Archive
# in a way that takes care of special characters
# and allows for correct handling of multiple
# conditions on WHERE queries, etc.
#################################################

package XAQ;   # Exoplanet Archive Query API wrapper

use LWP::Simple;

my $BURL="http://exoplanetarchive.ipac.caltech.edu/cgi-bin/nstedAPI/nph-nstedAPI?";

my $WC='%25';     # wildcard character
my $DELIM='\|';   # we used pipe-delimited output:  
                  # easier to parse than CSV with fields that may have embedded commas

sub wc    { return $WC }
sub delim { return $DELIM }

# the constructor can take an alternative base url as an optional argument
# data elements are:
#     b:  (simple string) base URL for queries
#     q:  (array ref) list of query items
#     w:  (array ref) list of where SELECT logic items

sub new {
  my $class=shift;
  my $s={};
  $s->{b}=shift() // $BURL;
  my $self=bless $s, $class;
  return $self->clear()->bar_format();
}

# these mutators return a reference to the object to allow cascading calls
# i.e., $object->clear()->bar_format(...)->add_where(...)->add_where(...)

sub clear               { my $self=shift; $self->{q}=[]; $self->{w}=[];             return $self }
sub add_query           { my $self=shift; push @{$self->{q}}, @_;                   return $self }
sub add_where           { my $self=shift; push @{$self->{w}}, shift();              return $self }
sub from_table          { my $self=shift; $self->add_query("table=".shift());       return $self }
sub bar_format          { my $self=shift; $self->add_query("format=bar");           return $self }
sub select_all          { my $self=shift; $self->add_query("select=*");             return $self }
sub select_col          { my $self=shift; $self->add_query("select=".join(',',@_)); return $self }
sub select_distinct_col { my $self=shift; $self->add_query('select=distinct%1E'.join(',',@_)); return $self }
             

sub like                { my $self=shift; my ($k,$v)=@_; $self->add_where("$k+like+'$v'"); return $self }
sub equals_str          { my $self=shift; my ($k,$v)=@_; $self->add_where("$k='$v'");      return $self }

# execute a query and provide the result as a single long string
# result takes a list of arguments for query logic additional queries, 
# typically specifying which table to use for the query.  Suggested
# usage is to call one of the "synonyms" for result(), below, which provide
# the correct argument to result for each table.

sub result {
  my $self=shift; 
  $self->add_query(@_) if scalar(@_);  # add any additional query items on argument list
  if (scalar(@{$self->{w}})) {         # have to handle where items explicitly to combine logic
    my $w="where=".join("+AND+",@{$self->{w}});
    $self->add_query($w);
  }
  my $q=$self->{b}.join("\&",@{$self->{q}});
  return get($q);
}

# execute query the query on a specific table -- just synonyms for result() from the appropriate table

sub exoplanets    { return shift()->from_table('exoplanets')->result    }
sub keplernames   { return shift()->from_table('keplernames')->result   }
sub cumulative    { return shift()->from_table('cumulative')->result    }
sub keplerstellar { return shift()->from_table('keplerstellar')->result }
sub q1_q16_tce    { return shift()->from_table('q1_q16_tce')->result    }
sub q1_q16_koi    { return shift()->from_table('q1_q16_koi')->result    }

#################################################
# The XA package makes use of the XAQ class
# do specific queries on Exoplanet Archive data
# and return content of interest to the rest
# of this script.
#################################################

package XA;         # Exoplanet Archive API access

my $WGET_URL="http://exoplanetarchive.ipac.caltech.edu/bulk_data_download/Kepler_TCE_DV_wget.bat";
use LWP::Simple;

use Data::Dumper;   # for diagnostic / error messages

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
sub kepler_stars      { my $self=shift; return ::uniq map { $self->{N}{$_}{kepid} } keys %{$self->{N}} }
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
# IPAC::AsciiTable package
# imported from separate module
# and adapted here as part of 
# standalone script.
#############################

package IPAC_AsciiTable;

use Data::Dumper;

sub identical_arrays {
  my $a1=shift;
  my $a2=shift;
  return 0 unless scalar(@$a1)==scalar(@$a2);
  for (my $i=0; $i<scalar(@$a1); $i++) { return 0 unless $a1->[$i]==$a2->[$i] }
  return 1;
}
  
sub trim_white { local $_=shift; s/^\s*//; s/\s*$//; return $_ }

sub max { my $m=shift; for (@_) { $m=($_>$m) ? $_ : $m } return $m }

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


=pod

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
	my @c=map { trim_white($_) } column_capture($_,@{$T->{M}});
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
	my @c=map { trim_white($_) } column_capture($_,@{$T->{M}});
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

#############################
# The main script follows -- 
# end of class definitions.
#############################

package main;

use Data::Dumper;

use LWP::Simple;
use Getopt::Long;
my %opt;
GetOptions (\%opt, 'q|quiet', 'tbl=s', 'keep_tbl', 'max=i');

print STDERR "perldoc $0 for help.\n" unless $opt{q};

# initializations and constants

sub web_page_exists { my $url=shift; return defined get($url); }

# die "Usage:  $0 kepler-name" unless scalar(@ARGV);

my $kname;

# $kname=join(' ',@ARGV);

print STDERR "Loading all Exoplanet Archive Tables\n" unless $opt{q};

my $X=new XA;
my @r=$X->kepler_names;

my $np=scalar(@r);                      # number of planets

my $i_np = 0;       # counter

print STDERR "Planets=$np\n" unless $opt{q};

for $kname (sort { $a cmp $b } @r) {

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

  my $xml_out=$kname;  $xml_out=~s/\s+/-/g; $xml_out.='.xml';
  open XML, ">$xml_out" or die "Couldn't create $xml_out";
  print XML gen_xml($meta,\@folded_time,\@data,\@model,\@time_filter);
  close XML;

  unlink $tempfile unless $opt{keep_tbl};   # cleanup

}

exit;

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

