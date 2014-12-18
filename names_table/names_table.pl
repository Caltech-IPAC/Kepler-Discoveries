#!/usr/bin/perl -w

=head1 Name 

names_table.pl - Generate updated HTML-formatted Rows for the Kepler Discoveries Table from the NASA Exoplanet Archive

=head1 Synopsis

  ./names_table.pl > table.html
  ./names_table.pl -comments -css -a -q > table.html
  ./names_table.pl -js -css -q > table.js

This script uses the NASA Exoplanet Archive (I<http://exoplanetarchive.ipac.caltech.edu>) API to
extract the complete list of confirmed planets from the Kepler Mission, and generate html rows in
a table of information for them using Exoplanet Archive data values corresponding to the Kepler Discoveries
table:  I<http://kepler.nasa.gov/Mission/discoveries/>

The last synopsis example above shows the use of the script to generate a javascript for inclusion in a web-page.
The first and second synopsis examples show the use of the script to generate a standalone html web page, which could
either be "cut and pasted" into another web-page, or included using a "Server-Side Include" directive.

=head1 Options

=over 4

=item -css

Convenience option to bracket the beginning and ending of the output with <style>..</style> CSS
formatting and other <html><body>...</body></html>, etc HTML to make the output a complete web-page for
immediate viewing in a browser.  Helpful for diagnostics.

=item -js

Format the output for a javascript include using the "document.write" function.  The output
will have a continuation mark (\\) at the end of every line.  
(By default, output is for a Server-Side includes.)  

=item -c -comments

Include html comments in the output.

=item -q -quiet

Execute without printing to STDERR "progress/status" and planet web-page found updates

=item -a -absolute_links

Make links in the first column absolute links to the Kepler Mission Discoveries pages,
rather than relative links.  By default, the links are relative.

=item -no_links

Do not look for Kepler Mission Discoveries Table links.  No hyperlinks to the Kepler Mission
Discoveries pages will be provided.

=back

=cut

use strict;
use Time::Piece;

sub uniq  { keys %{ { map { $_ => 1 } @_ } } }

sub today { return Time::Piece->new->strftime('%Y/%m/%d') }
sub now   { return localtime() }

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

#################################################
# The XA package makes use of the XAQ class
# do specific queries on Exoplanet Archive data
# and return content of interest to the rest
# of this script.
#################################################

package XA;         # Exoplanet Archive API access

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

# get all tables up front and parse into useful hashes
sub new { 
  my $class=shift; 
  my $self={};
  my $x;  # have to get a "clean" XAQ object for each call
  $x=new XAQ; $self->{N}=parse_table_by_index('kepler_name',$x->select_all()->keplernames,   $x->delim(),'Kepler Names');  
  $x=new XAQ; $self->{K}=parse_table_by_index('kepoi_name', $x->select_all()->cumulative,    $x->delim(),'Cumulative KOI');
  $x=new XAQ; $self->{X}=parse_table_by_index('pl_name',    $x->select_all()->exoplanets,    $x->delim(),'Confirmed Exoplanets'); 
  # Kepler Stellar kepid's are not unique, except within a particular delivery
  my $deliv=XA->latest_stellar_delivery();
  $x=new XAQ; $self->{S}=parse_table_by_index('kepid',      $x->select_all()->equals_str('st_delivname',$deliv)->keplerstellar, $x->delim(),'Kepler Stellar'); 
  return bless $self, $class;
}

# Short-cut accessors for table rows (returned as hashes of col_name==>row_value)
# Lookup to tables is for the following column names:
#     exoplanets:   pl_name
#     cumulative:   kepoi_name
#     keplernames:  kepler_name
# An improvement would be to check for existence of the lookup key value and 
# throw an error if not found.

sub kepler_names      { my $self=shift; return keys %{$self->{N}} }
sub kepoi_candidates  { 
  my $self=shift; 
  return grep { 
    ($self->{K}{$_}{koi_disposition}=~/(CANDIDATE|CONFIRMED)/)
  } keys %{$self->{K}}; 
}
sub kepler_stars      { my $self=shift; return ::uniq map { $self->{N}{$_}{kepid} } keys %{$self->{N}} }
sub kepler_multiples  { 
  my $self=shift; 
  return map { $self->{X}{$_}{pl_hostname} } grep { ($self->{X}{$_}{pl_kepflag}==1) && ($self->{X}{$_}{pl_pnum}>1) } keys %{$self->{X}};
}

sub exoplanet_planet_row   { my $self=shift; my $pname=shift; return $self->{X}{$pname} }
sub cumulative_kepoi_row   { my $self=shift; my $kepoi=shift; return $self->{K}{$kepoi} }
sub keplernames_planet_row { my $self=shift; my $kname=shift; return $self->{N}{$kname} }
sub keplerstellar_row      { my $self=shift; my $kepid=shift; return $self->{S}{$kepid} }


=head1 DESCRIPTION

names_table.pl performs the following actions:

=over 4

=item 

Query the NASA Exoplanet Archive to get a list of all confirmed planet names from the "Kepler Names" table.

=item 

For each confirmed planet name returned, perform queries to extract:

=over 4

=item 

The KepOI Name from the "Cumulative KOI" Table.

=item 

Planet parameters from the "Exoplanets" Table.

=item 

Stellar parameters from the "Exoplanets" Table.

=item 

Kepler Magnitude of the stellar host from the Cumulative KOI" Table.

=back

=item 

Write one output row in html format with these data for each of the confirmed planet names using a defined html template.

=back

=head2 Details

=head3 Column Name Mapping

The mapping between information in the NASA Exoplanet Archive tables and the Kepler Discovery Table
is summarized here.  The parameter names in parethesis are the "limit" flags for each parameter: 

    Kepler Discovery Col      Kepler Names Col   Confirmed Planets Col        Cumulative KOI Col
    ===================       ================   =====================        ==================
    Name                      kepler_name
    KOI #                     kepoi_name
    ---------------------------------------Planet Parms-----------------------------------------
    Jupiter Masses                               pl_massj (pl_masslim)                             
    Earth Masses                                 pl_masse (pl_masslim)
    Jupiter Radii                                pl_radj (pl_radjlim)
    Earth Radii                                  pl_rade (pl_radelim)         koi_prad
    density grams/cc                             pl_dens (pl_denslim)
    Temp Kelvin                                  pl_eqt (pl_eqtlim)           koi_teq
    Transit Duration days/hrs*                   pl_trandur (pl_trandurlim)   koi_duration 
    Orbit Period days                            pl_orbper (pl_orbperlim)     koi_period
    Orbit Semi-major axis AU                     pl_orbsmax (pl_orbsmaxlim)   koi_sma
    Orbit Eccentricity                           pl_orbeccen (pl_orbeccenlim)
    Orbit Inclination deg                        pl_orbincl (pl_orbincllim)   koi_incl
    ------------------------------------Stellar Host Parms--------------------------------------
    Distance parsecs                             st_dist (st_distlim)
    Effective temp K                             st_teff (st_tefflim)         koi_steff
    Solar Masses                                 st_mass (st_masslim)         koi_smass
    Solar Radii                                  st_rad  (st_radlim)          koi_srad
    Metalicity                                   st_metfe st_metfelim)        koi_smet
    RA (HH MM SS J2000)                          ra                           ra
    DEC (DEG MM SS J2000)                        dec                          dec
    Kp Mag*** (Kepler magnitude)                                              koi_kepmag
    -------------------------------------------------------------------------------------------
    Last Update**                                pl_publ_date                 koi_vet_date

*Transit duration units from the Confirmed Planets table are days, but in the Cumulative KOI
table are hours.  The Discovery table output is in hours.

**Note that for the Last Update parameter (and that parameter only), the date from the Cumulative KOI table
is used if available.  If not available, the publication date from the Confirmed Planets table is used.

***If koi_kepmag isn't available, the parameter is guaranteed to be in the Kepler stellar table,
parameter name is kepmag.

=head3 Logic

There is additional logic or calculation which is used to fill in missing values for cases
where the Cumulative KOI Mapping table does not have the same column as the Confirmed Planets table.

=over 4

=item Jupiter Mass

If the Jupiter Mass value is missing, calculate it from the Earth Mass parameter (if available) using a
constant conversion factor.  The constant $E_TO_J_MASS is 317.83

=item Jupiter Radius

If the Jupiter Radius value is missing, calculate it from the Earth Radius parameter (if available) using
a constant conversion factor.  The constant $E_TO_J_RADIUS is 11.209

=back

=cut

#############################
# The main script follows -- 
# end of class definitions.
#############################

package main;

use LWP::Simple;
use Getopt::Long;
my %opt;
GetOptions (\%opt, 'c|comments','css','q|quiet', 'a|absolute_links', 'debug', 'js', 'no_links'); 

print STDERR "perldoc $0 for help.\n" unless $opt{q};

# initializations and constants

my $E_TO_J_RADIUS=11.2089807;
my $E_TO_J_MASS=317.81661;

# parameter and format mapping

my %P = (
	 Kep =>           { f=>'%s' },
	 KOI =>           { f=>'%s' },
	 massE =>         { f=>'%0.2f',  e=>'pl_masse' },
	 massJ =>         { f=>'%0.4f',  e=>'pl_massj' },
	 radiusJ =>       { f=>'%0.4f',  e=>'pl_radj' },
	 radiusE =>       { f=>'%0.3f',  e=>'pl_rade',      k=>'koi_prad' },
	 density =>       { f=>'%0.3f',  e=>'pl_dens' },
	 tempPlanet =>    { f=>'%0.0f',  e=>'pl_eqt',       k=>'koi_teq' },
	 duration =>      { f=>'%0.4f',  e=>'pl_trandur',   k=>'koi_duration' },
	 period =>        { f=>'%0.8f',  e=>'pl_orbper',    k=>'koi_period' },
	 semimajoraxis => { f=>'%0.5f',  e=>'pl_orbsmax',   k=>'koi_sma' },
	 eccentricity =>  { f=>'%0.3f',  e=>'pl_orbeccen' },
	 inclination =>   { f=>'%0.3f',  e=>'pl_orbincl',   k=>'koi_incl' },
	 distance =>      { f=>'%0.0f',  e=>'st_dist' },
	 tempStar =>      { f=>'%0.0f',  e=>'st_teff',      k=>'koi_steff' },
	 massStar =>      { f=>'%0.3f',  e=>'st_mass',      k=>'koi_smass' },
	 radiusStar =>    { f=>'%0.3f',  e=>'st_rad',       k=>'koi_srad' },
	 metallicity =>   { f=>'%+0.3f', e=>'st_metfe',     k=>'koi_smet' },
	 RA =>            { f=>'%s',     e=>'ra',           k=>'ra' },
	 Dec =>           { f=>'%s',     e=>'dec',          k=>'dec' },
	 Kp =>            { f=>'%6.3f',                     k=>'koi_kepmag' },
	 lastupdated =>   { f=>'%s',     e=>'pl_publ_date', k=>'koi_vet_date' }
);

# add limit flags for certain parameters
for (qw( radiusJ radiusE density tempPlanet duration period semimajoraxis
	 eccentricity inclination distance tempStar massStar radiusStar metallicity )) {
  $P{$_}{l}=$P{$_}{e}.'lim';
}
for (qw( massE massJ )) { $P{$_}{l}='pl_masslim' }

# add CSS classes in groups
for (qw( Kep KOI massE massJ radiusJ radiusE density tempPlanet
	 duration period semimajoraxis eccentricity inclination )) {
  $P{$_}{c}='TdBlue1';
}
for (qw( tempStar massStar radiusStar metallicity RA Dec Kp )) {
  $P{$_}{c}='TdBrown1';
}
for (qw( distance lastupdated )) { $P{$_}{c}='TdGrey1' }

# output routine to turn html into javascript
# requires escaping any embedded single-quote 
# character; replacing it with an html escape code.

sub js_print {
  my @out;
  my $html_single_quote='&#39;';
  if ($opt{js}) { 
    for my $o (@_) { 
      push @out, map { s/[']/$html_single_quote/g; $_ } map { $_.' \\'."\n" } split("\n",$o);
    }
  } else { @out=@_ }
  print for @out;
}

# common output stuff used by output and output_link

sub _output($$) {
  my ($o,$x)=@_;
  my $a=$o->{$x};
  my $s=$P{$x}{c};
  my $f=exists $P{$x}{f} ? $P{$x}{f} : '%s';
  my $v='&#151;';  # html for an em-dash
  if ((defined $a) && ($a cmp '')) {
    $v=sprintf($f,$a);
    if ($o->{$x."_is_limit"}) { $v=$o->{$x."_is_limit"}.$v }
  }
  my $c='<!--'.$x.'-->';
  return ($c,$v,$s)
}
  
# arguments are:
#    hash of output values (%O)
#    key to hash for this output line

sub output(\%$) {
  my ($c,$v,$s)=_output $_[0], $_[1];
  my $h='<td class="'.$s.'">';
  return "$c$h$v".'</td>'."\n" if $opt{c};
  return "$h$v".'</td>'."\n";
}

# arguments are:
#    hash of output values (%O)
#    key to hash for this output line
#    url of hyperlink

sub output_link(\%$$$) {
  my $np=pop @_;
  my $l=pop @_;
  my ($c,$v,$s)=_output $_[0], $_[1];
  my $tb=$np ? 'target="_blank" ' : '';
  my $h=q(<td class=").$s.q("><a ).$tb.q(href=").$l.q(">).$v.q(</a>);
  return "$c$h".'</td>'."\n" if $opt{c};
  return     $h.'</td>'."\n";
}

# helper functions to ensure initialization, possibly with backup values

sub initialized($)  { my $a=shift; return ((defined $a) && ($a ne '')); }
sub single_init($)  { my ($i1)    =@_; return initialized $i1 ? $i1 : undef; }
sub double_init($$) { my ($i1,$i2)=@_; return initialized $i1 ? $i1 : initialized $i2 ? $i2 : undef; }
sub web_page_exists { my $url=shift; return defined get($url); }

# # (DISABLED)
# # attempt to find a web-page for kepler name, handling special cases
# # first try page for the name, then page for name without planet letter
# # then look for special cases:  48b60d and 47bc
# 
# my %missing_pages = map { ($_,1) } (qw( 
# 					32d 32e 32f 39b 40b 41b 42b 42c 42d 43b 44b 45b 46b 46c
# 					61b 63b 66b 67b 70b 70c 71b 74b 75b 76b 86b 87b 87c 88b 88c
# 					89b 89c 89d 89e 90b 90c 90d 90e 90f 90g 90h
# 				     ));
# 
# # (END DISABLED PART)

sub get_kdt_page {
  my $kepname=shift;  # format is Kepler-N [A ]a
  my ($n,$a)=($kepname=~/^Kepler-(\d+)\s+((?:\w\s*)+)$/);
  $a=~s/\s+//g;  # no white-space for web-page url in component and planet suffix
  my $kdt_base="http://kepler.nasa.gov";
  my $kdt_base_return=$opt{a} ? $kdt_base : '';
  my $kdt_rel ="/Mission/discoveries/kepler";
  return undef if $opt{no_links};
# disable logic for excluded planets
#   return undef if $missing_pages{"$n$a"}; # list of broken links -- exclude these
  return "$kdt_base_return$kdt_rel$n$a";  # this is the new version -- no checking
}

sub init(\%$$$) {
  my $o=shift;  # target hash to initialize
  my $a=shift;  # first hash-ref source 
  my $b=shift;  # secondary hash-ref source
  my $k=shift;  # key in target hash
  if (exists $P{$k}{k}) {
    if (exists $P{$k}{e}) {    # primary and secondary sources
      $o->{$k}=double_init $a->{$P{$k}{e}}, $b->{$P{$k}{k}};
    } else {                   # secondary only
      $o->{$k}=single_init $b->{$P{$k}{k}};
    }                          
  } elsif (exists $P{$k}{e}) { # primary only
    $o->{$k}=single_init $a->{$P{$k}{e}};
  } else {                     # this shouldn't happen
    die "init called for parameter $k with no initialization source";
  }
}

print STDERR "Loading all Exoplanet Archive Tables\n" unless $opt{q};

my $X=new XA;
my @r=$X->kepler_names;

my $nc=scalar($X->kepoi_candidates());  # number of Kepler Candidates
my $np=scalar(@r);                      # number of planets
my $ns=scalar($X->kepler_stars());      # number of Kepler host stars
my $nm=scalar(::uniq $X->kepler_multiples());            # number of Kepler host stars with multiple planet systems

my $i_np = 0;       # counter

print STDERR "Planets=$np; Candidates=$nc\n" unless $opt{q};

print_table_head($np,$nc,$ns,$nm);

# step through Kepler names, sorted

for my $p ( sort { my ($aa)=($a=~/-(\d+)/); 
		   my ($bb)=($b=~/-(\d+)/); 
		   ($aa<=>$bb) || ($a cmp $b) } @r ) {

  print STDERR "Fetching data for $p (planet @{[ ++$i_np ]} of $np)\n" unless $opt{q};

  my $n=$X->keplernames_planet_row($p);
  die "No Exoplanet Table Entry Name!\n" unless $n->{alt_name};

  my $e=$X->exoplanet_planet_row($n->{alt_name});
  my ($kepoi_number)=($n->{kepoi_name}=~/K0*([1-9]\d*\.\d\d)/);  # undef if no match
  my $koi_base='http://exoplanetarchive.ipac.caltech.edu/cgi-bin/DisplayOverview/nph-DisplayOverview?objname=';
  my $koi_link;
  my $c={};  # if koi_list_flag is false, then no data from cumulative table in $c
  unless ($n->{koi_list_flag} cmp 'YES') {
    $c=$X->cumulative_kepoi_row($n->{kepoi_name});
    $koi_link="$koi_base$n->{kepoi_name}".'&type=KEPLER_CANDIDATE';
  } 

  my $s=$X->keplerstellar_row($n->{kepid});

  my %O;
  $O{Kep}=$p; 
  $O{Kep}=~s/\s+//g; 

  $O{KOI}       = single_init $kepoi_number;
  $O{massE}     = single_init $e->{pl_masse};

  unless (defined $O{massE}) { # try to set a mass limit instead
    if (initialized $e->{pl_msinie}) {
      $O{massE}=$e->{pl_msinie};
      $O{massE_is_limit}='>';
      unless (initialized $e->{pl_massj}) {  # don't use if we have a jupiter mass
	$O{massJ}=$e->{pl_msinie}/$E_TO_J_MASS;
	$O{massJ_is_limit}='>';
      }
    }
  } 

  # do the same thing for massJ as for massE, but can initialize from massE
  $O{massJ}          = initialized $e->{pl_massj}  ? $e->{pl_massj}        : initialized         $O{massE}  ?     $O{massE}/$E_TO_J_MASS : undef;

  # already checked for pl_msinie above

  # straightforward initializations
  for (qw( radiusE density tempPlanet period semimajoraxis eccentricity 
	   inclination distance tempStar massStar radiusStar metallicity )) {
    init %O, $e, $c, $_;
  }

  # special cases

  $O{radiusJ}      = initialized $e->{pl_radj}     ? $e->{pl_radj}         : initialized $O{radiusE}        ? $O{radiusE}/$E_TO_J_RADIUS : undef;
  $O{duration}     = initialized $e->{pl_trandur}  ? $e->{pl_trandur}*24.0 : initialized $c->{koi_duration} ? $c->{koi_duration}         : undef;
  $O{RA}           = initialized $e->{ra}          ? ra_str($e->{ra} )     : initialized $c->{ra}           ? ra_str($c->{ra})           : undef;
  $O{Dec}          = initialized $e->{dec}         ? dec_str($e->{dec})    : initialized $c->{dec}          ? dec_str($c->{dec})         : undef;

  $O{Kp}           = double_init $c->{koi_kepmag},   $s->{kepmag};
  $O{lastupdated}  = double_init $c->{koi_vet_date}, $e->{pl_publ_date};  # eventually, should be row_update_date when available.

  # set all limit flags

  for (keys %O) {
    if (exists $P{$_}{l}) { 
      my $l=$e->{$P{$_}{l}};
      $O{$_.'_is_limit'} //= ($l>0) ? '<' : ( $l<0 ? '>' : '' ) if $l;  # don't change if already set by other logic
    }
  }

  js_print '<tr>'."\n";

  my $kdt_webpage;
  if ($kdt_webpage=get_kdt_page($p)) {
    js_print output_link %O, 'Kep', $kdt_webpage, 0;  # 0==don't display new page on open
  } else {
    js_print output %O, 'Kep';
  }

  if (defined $koi_link) {
    js_print output_link %O, 'KOI', $koi_link, 1;   # 1==display new page on open
  } else {
    js_print output %O, 'KOI';
    print STDERR "***No Exoplanet Archive KepOI details for $p\n" unless $opt{q};
  }

  js_print output %O, $_
    for qw( massJ massE radiusJ radiusE density tempPlanet 
	    duration period semimajoraxis eccentricity inclination distance
	    tempStar massStar radiusStar metallicity RA Dec Kp lastupdated );

  js_print '</tr>'."\n";

}

print_table_end();



###########################
# HTML/CSS for table,
# used for diagnostics, not
# really needed for script.
###########################

sub print_table_head {

  my $np=shift;
  my $nc=shift;

  if ($opt{js}) {
    print "document.write(' \\";
  }

  if ($opt{css}) {
    my $time=now();
    js_print "<html>\n<head>\n";
    js_print "<title>Kepler Discoveries</title>\n";
    js_print "<p>Updated by $0 at $time</p>\n";
  }

  js_print <<END_CSS if $opt{css};
  <style type="text/css">
    table.customTbl
    {
    border-collapse:collapse;
    }
    table.customTbl, table.customTbl th, table.customTbl td {
    border: 1px solid white !important; padding:3px;
    }
    td.HdrBlue2Bold, td.HdrGrey2Bold, td.HdrBrown2Bold, td.HdrBlue3Bold, td.HdrGrey3Bold, td.HdrBrown3Bold {
    	padding:3px 2px 3px 2px !important; 
    }
    td.HdrBlue1Bold {
    color:#fffefd;
    font-size:15px;
    font-weight:bold;
    background-color:#0d2142;
    text-align:center !important;
    vertical-align:middle;
    }
    td.HdrGrey1Bold {
    color:#000000;
    font-size:15px;
    font-weight:bold;
    background-color:#909090;
    text-align:center !important;
    vertical-align:middle;
    }
    td.HdrBrown1Bold {
    color:#fffefd;
    font-size:15px;
    font-weight:bold;
    background-color:#664b20;
    text-align:center !important;
    vertical-align:middle;
    }
    td.HdrBlue2Bold {
    color:#fffefd;
    font-size:12px;
    font-weight:bold;
    background-color:#143264;
    text-align:center !important;
    vertical-align:middle;
    }
    td.HdrGrey2Bold {
    color:#000000;
    font-size:12px;
    font-weight:bold;
    background-color:#d1d1d1;
    text-align:center !important;
    vertical-align:middle;
    }
    td.HdrBrown2Bold {
    color:#fffefd;
    font-size:12px;
    font-weight:bold;
    background-color:#87642a;
    text-align:center !important;
    vertical-align:middle;
    }
    td.HdrBlue3BoldItalic {
    color:#fffefd;
    font-size:12px;
    font-weight:bold;
    background-color:#2c4c7f;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    td.HdrGrey3BoldItalic {
    color:#000000;
    font-size:12px;
    font-weight:bold;
    background-color:#d1d1d1;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    td.HdrBrown3BoldItalic {
    color:#fffefd;
    font-size:12px;
    font-weight:bold;
    background-color:#a57f40;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    td.HdrBlue3Italic {
    color:#fffefd;
    font-size:12px;
    background-color:#2c4c7f;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    td.HdrGrey3Italic {
    color:#000000;
    font-size:12px;
    background-color:#d1d1d1;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    td.HdrBrown3Italic {
    color:#fffefd;
    font-size:12px;
    background-color:#a57f40;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    td.TdBlue1 {
    color:#000000;
    font-size:12px;
    background-color:#becee7;
    text-align:center !important;
    vertical-align:middle;
    border-top:2px !important; border-bottom:2px !important;
    }
    td.TdGrey1 {
    color:#000000;
    font-size:12px;
    background-color:#e8e8e8;
    text-align:center !important;
    vertical-align:middle;
    border-top:2px !important; border-bottom:2px !important;
    }
    td.TdBrown1 {
    color:#000000;
    font-size:12px;
    background-color:#e3d0a6;
    text-align:center !important;
    vertical-align:middle;
    border-top:2px !important; border-bottom:2px !important;
    }
    td.TdSpacerBlue1 {
    color:#fffefd;
    font-size:12px;
    background-color:#0d2142;
    text-align:left;
    vertical-align:middle;
    height: 8px;
    }
    td.TdSpacerGrey1 {
    color:#000000;
    font-size:12px;
    background-color:#909090;
    text-align:left;
    vertical-align:middle;
    height: 8px;
    }
    td.TdSpacerBrown1 {
    color:#fffefd;
    font-size:12px;
    background-color:#664b20;
    text-align:left;
    vertical-align:middle;
    height: 8px;
    }
    th.HdrBlue2Bold, th.HdrGrey2Bold, th.HdrBrown2Bold, th.HdrBlue3Bold, th.HdrGrey3Bold, th.HdrBrown3Bold {
    	padding:3px 2px 3px 2px !important; 
    }
    th.HdrBlue1Bold {
    color:#fffefd;
    font-size:15px;
    font-weight:bold;
    background-color:#0d2142;
    text-align:center !important;
    vertical-align:middle;
    }
    th.HdrGrey1Bold {
    color:#000000;
    font-size:15px;
    font-weight:bold;
    background-color:#909090;
    text-align:center !important;
    vertical-align:middle;
    }
    th.HdrBrown1Bold {
    color:#fffefd;
    font-size:15px;
    font-weight:bold;
    background-color:#664b20;
    text-align:center !important;
    vertical-align:middle;
    }
    th.HdrBlue2Bold {
    color:#fffefd;
    font-size:12px;
    font-weight:bold;
    background-color:#143264;
    text-align:center !important;
    vertical-align:middle;
    }
    th.HdrGrey2Bold {
    color:#000000;
    font-size:12px;
    font-weight:bold;
    background-color:#d1d1d1;
    text-align:center !important;
    vertical-align:middle;
    }
    th.HdrBrown2Bold {
    color:#fffefd;
    font-size:12px;
    font-weight:bold;
    background-color:#87642a;
    text-align:center !important;
    vertical-align:middle;
    }
    th.HdrBlue3BoldItalic {
    color:#fffefd;
    font-size:12px;
    font-weight:bold;
    background-color:#2c4c7f;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    th.HdrGrey3BoldItalic {
    color:#000000;
    font-size:12px;
    font-weight:bold;
    background-color:#d1d1d1;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    th.HdrBrown3BoldItalic {
    color:#fffefd;
    font-size:12px;
    font-weight:bold;
    background-color:#a57f40;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    th.HdrBlue3Italic {
    color:#fffefd;
    font-size:12px;
    background-color:#2c4c7f;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    th.HdrGrey3Italic {
    color:#000000;
    font-size:12px;
    background-color:#d1d1d1;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    th.HdrBrown3Italic {
    color:#fffefd;
    font-size:12px;
    background-color:#a57f40;
    text-align:center !important;
    vertical-align:middle;
    font-style: italic;
    }
    th.TdBlue1 {
    color:#000000;
    font-size:12px;
    background-color:#becee7;
    text-align:center !important;
    vertical-align:middle;
    border-top:2px !important; border-bottom:2px !important;
    }
    th.TdGrey1 {
    color:#000000;
    font-size:12px;
    background-color:#e8e8e8;
    text-align:center !important;
    vertical-align:middle;
    border-top:2px !important; border-bottom:2px !important;
    }
    th.TdBrown1 {
    color:#000000;
    font-size:12px;
    background-color:#e3d0a6;
    text-align:center !important;
    vertical-align:middle;
    border-top:2px !important; border-bottom:2px !important;
    }
    th.TdSpacerBlue1 {
    color:#fffefd;
    font-size:12px;
    background-color:#0d2142;
    text-align:left;
    vertical-align:middle;
    height: 8px;
    }
    th.TdSpacerGrey1 {
    color:#000000;
    font-size:12px;
    background-color:#909090;
    text-align:left;
    vertical-align:middle;
    height: 8px;
    }
    th.TdSpacerBrown1 {
    color:#fffefd;
    font-size:12px;
    background-color:#664b20;
    text-align:left;
    vertical-align:middle;
    height: 8px;
    }
  </style>
</head>
  <body>
END_CSS

js_print <<END_TABLE_HEAD;

<!-- Number of Kepler Planets:                      $np -->
<!-- Number of Kepler Candidates:                   $nc -->
<!-- Number of Kepler Stars:                        $ns -->
<!-- Number of Kepler Stars with Multiple Planets:  $nm -->

<table cellpadding="0" cellspacing="0" border="0" class="customTbl" id="example"   style="width: 1280px">
<thead>
<tr> 
<th class="HdrBlue1Bold"  width="7%">&nbsp;</th> 
<th colspan="7" class="HdrBlue1Bold">Planetary Characteristics</th> 
<th colspan="5" class="HdrBlue1Bold">Planetary Orbit</th> 
<th class="HdrGrey1Bold">&nbsp;</th> 
<th colspan="7" class="HdrBrown1Bold">Stellar Characteristics</th> 
<th class="HdrGrey1Bold">&nbsp;</th> 
</tr> 
<tr> 
<th class="HdrBlue2Bold">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Name&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th> 
<th class="HdrBlue2Bold" width=4%>KOI #</th> 
<th colspan="2" class="HdrBlue2Bold">Mass</th> 
<th colspan="2" class="HdrBlue2Bold">Radius</th> 
<th class="HdrBlue2Bold">Density</th> 
<th class="HdrBlue2Bold">Temp*</th> 
<th class="HdrBlue2Bold">Transit<br>Duration</th> 
<th class="HdrBlue2Bold">Period</th> 
<th class="HdrBlue2Bold">Semi-<br>Major axis</th> 
<th class="HdrBlue2Bold">Eccen-<br>tricity</th> 
<th class="HdrBlue2Bold">Inclin-<br>ation**</th> 
<th class="HdrGrey2Bold">Distance</th> 
<th class="HdrBrown2Bold">Effective Temp</th> 
<th class="HdrBrown2Bold">Stellar Mass</th> 
<th class="HdrBrown2Bold">Stellar Radius</th> 
<th class="HdrBrown2Bold" width=4%>Metal-<br>licity***</th> 
<th class="HdrBrown2Bold">Right Ascension&nbsp;&nbsp;</th> 
<th class="HdrBrown2Bold" width=6%>Declination</th> 
<th class="HdrBrown2Bold">Kp</th> 
<th class="HdrGrey2Bold" width=5%>Last<br>Updated</th> 
</tr> 
<tr> 
<th class="HdrBlue3Italic">&nbsp; </th> 
<th class="HdrBlue3Italic">&nbsp; </th> 
<th class="HdrBlue3Italic">Jupiter <br>masses</th> 
<th class="HdrBlue3Italic">Earth <br>masses</th> 
<th class="HdrBlue3Italic">Jupiter <br>radii</th> 
<th class="HdrBlue3Italic">Earth <br>radii</th> 
<th class="HdrBlue3Italic">grams/cc</th> 
<th class="HdrBlue3Italic">Kelvin</th> 
<th class="HdrBlue3Italic">hours</th> 
<th class="HdrBlue3Italic">days</th> 
<th class="HdrBlue3Italic">AU</th> 
<th class="HdrBlue3Italic">&nbsp; </th> 
<th class="HdrBlue3Italic">degrees</th> 
<th class="HdrGrey3Italic">parsecs</th> 
<th class="HdrBrown3Italic">Kelvin</th> 
<th class="HdrBrown3Italic">Solar masses</th> 
<th class="HdrBrown3Italic">Solar radii</th> 
<th class="HdrBrown3Italic">&nbsp; </th> 
<th class="HdrBrown3Italic">hh mm ss<br>J2000</th> 
<th class="HdrBrown3Italic">deg mm ss<br>J2000</th> 
<th class="HdrBrown3Italic"> Mag</th> 
<th class="HdrGrey3Italic">&nbsp; </th> 
</tr> 
</thead>

<tbody>
<tr> 
<td class="TdSpacerBlue1" colspan="13">Earth and Jupiter for comparison:</td> 
<td class="TdSpacerGrey1"></td> 
<td class="TdSpacerBrown1" colspan="7">Sun for comparison:</td> 
<td class="TdSpacerGrey1"></td> 
</tr> 
<tr> 
<td class="TdBlue1">Earth</td> 
<td class="TdBlue1">&nbsp;</td> 
<td class="TdBlue1">0.00314</td> 
<td class="TdBlue1">1.000</td> 
<td class="TdBlue1">0.089</td> 
<td class="TdBlue1">1.000</td> 
<td class="TdBlue1">5.515</td> 
<td class="TdBlue1">255/288</td> 
<td class="TdBlue1"></td> 
<td class="TdBlue1">365.25</td> 
<td class="TdBlue1">1.000</td> 
<td class="TdBlue1">0.016</td> 
<td class="TdBlue1">&nbsp;</td> 
<td class="TdGrey1">&nbsp;</td> 
<td class="TdBrown1">5780</td> 
<td class="TdBrown1">1.000</td> 
<td class="TdBrown1">1.000</td> 
<td class="TdBrown1">0.00</td> 
<td class="TdBrown1">&nbsp;</td> 
<td class="TdBrown1">&nbsp;</td> 
<td class="TdBrown1">&nbsp;</td> 
<td class="TdGrey1">&nbsp;</td> 
</tr> 
<tr> 
<td class="TdBlue1">Jupiter</td> 
<td class="TdBlue1">&nbsp;</td> 
<td class="TdBlue1">1.000</td> 
<td class="TdBlue1">317.82</td> 
<td class="TdBlue1">1.00</td> 
<td class="TdBlue1">11.21</td> 
<td class="TdBlue1">1.33</td> 
<td class="TdBlue1">124</td> 
<td class="TdBlue1"></td> 
<td class="TdBlue1">4330.60</td> 
<td class="TdBlue1">5.204</td> 
<td class="TdBlue1">0.0484</td> 
<td class="TdBlue1">&nbsp;</td> 
<td class="TdGrey1">&nbsp;</td> 
<td class="TdBrown1">5780</td> 
<td class="TdBrown1">1.000</td> 
<td class="TdBrown1">1.000</td> 
<td class="TdBrown1">0.00</td> 
<td class="TdBrown1">&nbsp;</td> 
<td class="TdBrown1">&nbsp;</td> 
<td class="TdBrown1">&nbsp;</td> 
<td class="TdGrey1">&nbsp;</td> 
</tr> 
<tr> 
<td class="TdSpacerBlue1" colspan="13">The first 3 planets listed were discovered prior to the <em>Kepler Mission</em> using ground-based observations. <br>They are listed to allow for inclusion of improved planetary and stellar properties from the Kepler data.</td> 
<td class="TdSpacerGrey1"></td> 
<td class="TdSpacerBrown1" colspan="7"></td> 
<td class="TdSpacerGrey1"></td> 
</tr>
END_TABLE_HEAD

}


sub print_table_end {

  js_print <<END_FOOTER;
</tbody>
</table>
END_FOOTER

  js_print "</body>\n</html>\n" if $opt{css};
  print "');\n" if $opt{js};
}

###############
# End of Script
###############

=head1 LICENSE

See LICENSE.txt file distributed with this software for license and copyright information.

=head1 TODO

Known items to be implemented and issues to be addressed.

=over 4

=item

No "row update" available for confirmed planets table yet.  Using publication date for now, but should replace with 
row_last_update once available.  (In any case, using koi_vet_date for all planets with KOI entries.)

=back

=head2 Questions and Clarifications Needed (now assumed resolved)

The following is a list of questions which remain, with answers embedded as they become known:

=over 4

=item 

Is the current target name correct?  In the kepler.nasa.gov table, sometimes two names are given.

Table is functioning correctly as generated by script, so assume this is now correct.

=item

Numerical Precision formatting requirements on all columns?

Assume formatting is correct as now implemented.

=item

Format for values when none are available?  Currently an em-dash (html code &#39;).

Assume correct.

=back

=head2 Prior Questions (now answered)

=over 4

=item

Are the metallicity parameters as defined by the Confirmed Planets and the Cumulative KOI tables the same?

Yes.

=item

What are the correct values for E_TO_J_RADIUS and E_TO_J_MASS?

From Tracy Chen email 2013-06-13:

  Here are the conversion values we use for planet radius and mass: 
  
  me = mj*317.816611 
  re = rj*11.2089807
  rs = rj*0.102792236
  
  *me, re = mass, radius in Earth unit; mj, rj = mass, radius in Jupiter unit; rs = radius in Sun unit.

=item

Would we ever have the Jupiter radius but not the earth radius?  (Can do, but more complicated logic when
we can't assume which one would always be available.)

No.  Only have Earth Radius in the Cumulative KOI table, and Confirmed Planets table is always
guaranteed to have both if it has one of them.  So can start with defining earth radius.

=item

Calculation for density if missing, using earth (or Jupiter?) radius and mass parameter values?

Apparently, no calculation to be done for density if missing.

=item

Do we have some fields which should be quoted as limits, rather than as value?

Yes, for the following items:

=over 4

=item Mass

Mass is only in the Confirmed Planets table, not in the Cumulative KOI table.  If there is not an earth mass in the
Confirmed Planets table, check to see if there is an M sin I value in the Confirmed Planets table.  If there
is, use that value with a prepended '>' as the value (actually 2a limit) for the mass.

Then use the conversion of Earth mass to Jupiter mass to fill in the Jupiter Mass value, also with a '>' prepended.

=back

Any other items?  Yes, as it turns out, almost all of the exoplanet table parameters have associated limit flags.
The table in the Column Name Mapping section has been updated to include the limit flag parameter names, 
and the script has been updated to look for limits on any of the parameters.

Note that the limit value of +1 means '>' -- i.e., a lower limit, while a flag value of -1 means '<' -- i.e., an
upper limit.  Some flag values are '0', and some are undefined.  I don't know if there is any difference between 
these two cases.

=item

Hyperlinks (URL) to use for KOI # entry?

Linked to the KepOI details page on the exoplanet archive for the KepOI:

    http://exoplanetarchive.ipac.caltech.edu/cgi-bin/DisplayOverview/nph-DisplayOverview?objname=KEPOI_NAME&type=KEPLER_CANDIDATE

where KEPOI_NAME is replaced with an actual KepOI Name, e.g. K00701.01.  
These are only used when the Kepler Names koi_list_flag is set to YES.

=item

Is the NNN.NN format for the KOI # column correct? 

Yes.

=item 

What is the correct logic for the lastupdated value?

If available, use the koi_vet_date from the cumulative table.  If there is not a KOI entry, then in principle we want the row_update_date 
from the confirmed planets table.  However, that column is not available, so for now we use the pl_publ_date (publication date).

=item

Missing the planet effective temperature in the Confirmed Planets table.

Once this is available via the API, need to confirm the column name in the script code.

Now available:  pl_eqt.

=back

=head1 CHANGES

=over 4

=item 2014-06-27

Removed commented-out code which is no longer used.
Added number of Kepler stars and number of Kepler stars with multiple planets:
  * Added ::uniq global function for convenience (removes duplicates from an array)
  * Added convenience member functions for these to the XA package
  * Added results of function calls to comment output in table
Cleaned up remaining ToDo items from prior delivery.

=item 2013-12-19

Fixed problem resulting from Build 5.1 of the NASA Exoplanet Archive:
Assumption that the KepIDs in the Kepler Stellar Table are unique is
no longer valid.  Combination of delivery and kepid is unique.  So updated
names_table.pl to find the most recent delivery name, and only select
kepids from that delivery.

Also corrected issue with constructing Kepler Mission page URLs for
planets around stellar components, e.g., Kepler-410 A b.  URL will be
constructed to have no white-space.

=item 2013-11-06

Changed the planet candidate count logic in the comments.  Previously the
count was obtained by selecting koi_pdisposition eq 'CANDIDATE'.  Now,
it is the set of koi_disposition =~ CANDIDATE | CONFIRMED, which is the
way that the Exoplanet Archive does the count.

=item 2013-11-05

As a result of the telecon with the customer, changed the default mode to
be the "Server-Side Include" model (removed the -ssi) option, and made
the Javascript "document.write()" mode an option:  -js.

Disabled the "missing_planets" logic.

Fixed a bug in the column count for pipe-delimited columns.  If the final
column is empty, it was excluded from the count, throwing off the count
between headers and data rows.

=item 2013-09-20

Added planet candidate count in html comments just before table

=item 2013-07-10

Changed options to separate making a standalone table from including the CSS
stylesheets.  

Added 'js_print' subroutine to turn output into "JavaScript" format, with continuation
characters at the end of every line.  This is the default output format, but new 
'-ssi' option ("Server Side Include") returns output format to original straight html.

Changed "undefined" entries from 'NA' to em-dashes.

=back

=head1 AUTHOR

  Dr. David A. Imel, <imel@caltech.edu>
  IPAC/NExScI California Institute of Technology
  2013-07-10

=cut

