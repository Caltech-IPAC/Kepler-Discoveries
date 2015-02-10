package XAQ;   # Exoplanet Archive Query API wrapper

=head1 Name 

XAQ.pm - Generate and Execute queries to the NASA Exoplanet Archive

=head1 Synopsis

  use lib 'Kepler-Discoveries/lib';  # insert correct path here
  use XAQ;

=head1 Description

The XAQ package is used to build URL-based queries to the Exoplanet Archive 
in a way that takes care of special characters and allows for correct handling 
of multiple conditions on WHERE queries, etc.

=cut

use strict;
use warnings;
use LWP::Simple;

our $DEFAULT_INTERNAL=1;

my $BURL="http://exoplanetarchive.ipac.caltech.edu";
my $APIQ="cgi-bin/nstedAPI/nph-nstedAPI?";

my $WC='%25';     # wildcard character
my $DELIM='\|';   # we used pipe-delimited output:  
                  # easier to parse than CSV with fields that may have embedded commas

sub wc    { return $WC }
sub delim { return $DELIM }

sub set_default_internal { $DEFAULT_INTERNAL=1 }
sub set_default_external { $DEFAULT_INTERNAL=0 }
 
# the constructor can take an alternative base url as an optional argument
# data elements are:
#     b:  (simple string) base URL for queries
#     a:  (simple string) API query prefix
#     q:  (array ref) list of query items
#     w:  (array ref) list of where SELECT logic items

sub new {
  my $class=shift;
  my $s={};
  my $self=bless {}, $class;
  $self->{a}=$APIQ;
  if ($DEFAULT_INTERNAL) { $self->set_internal_site() } else { $self->set_external_site() }
  return $self->clear()->bar_format();
}

sub set_internal_site { my $self=shift; $self->{b}=$BURL.":8000" }
sub set_external_site { my $self=shift; $self->{b}=$BURL         }
sub base_url          { my $self=shift; return $self->{b}        }

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
  my $q=$self->base_url().'/'.$APIQ.join("\&",@{$self->{q}});
  print STDERR "Executing API Query-->$q<--\n";
  return get($q);
}

# execute query the query on a specific table -- just synonyms for result() from the appropriate table

sub exoplanets    { return shift()->from_table('exoplanets')->result    }
sub keplernames   { return shift()->from_table('keplernames')->result   }
sub cumulative    { return shift()->from_table('cumulative')->result    }
sub keplerstellar { return shift()->from_table('keplerstellar')->result }
sub q1_q16_tce    { return shift()->from_table('q1_q16_tce')->result    }
sub q1_q16_koi    { return shift()->from_table('q1_q16_koi')->result    }

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
