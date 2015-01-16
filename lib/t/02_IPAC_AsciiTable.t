#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;
use LWP::Simple;

=head1 Name - 02_IPAC_AsciiTable.t

Execute tests for the Utilities.pm module.

=head1 Synopsis

  ./02_IPAC_AsciiTable.t

The paths are set up for executing the tests within the folder
where the scripts are.

=cut

my $path;

BEGIN {
  use File::Basename;
  $path=dirname($0);
}

BEGIN {
  use lib "$path/..";
  use_ok('IPAC_AsciiTable');
  use_ok('Utilities', qw( tw ) );
}


subtest "module functions" => sub {
  my @subs=qw( marker_capture column_capture _output_row new_empty new_from_file new
	       n_cols col_name n_data_rows row col extract add_col output_row );
  for (@subs) { can_ok('IPAC_AsciiTable',$_) }
};

subtest "marker_capture" => sub {
  is_deeply( [ IPAC_AsciiTable::marker_capture('| |  ||     | ')     ], [ (0,2,5,6,12) ], "marker capture finds columns with pipes" );
  is_deeply( [ IPAC_AsciiTable::marker_capture('|\|ab||\\-^  | ')    ], [ (0,2,5,6,12) ], "marker capture finds columns with special chars" );
  is_deeply( [ IPAC_AsciiTable::marker_capture(', ,  ,,     , ',',') ], [ (0,2,5,6,12) ], "marker capture finds columns with commas" );
};;

subtest "column_capture" => sub {
  my @r=('abcde ','ff','\ghd','   ',' @@^&^#(!');
  my $s='|'.join('|',@r).'|';
  is_deeply( [ IPAC_AsciiTable::column_capture($s,IPAC_AsciiTable::marker_capture($s)) ], [ @r ],  "column capture, using marker capture" );
  
  $s=join('|',@r);   # missing start and ending delimeters
  is_deeply( [ IPAC_AsciiTable::column_capture($s,IPAC_AsciiTable::marker_capture($s)) ], [ @r[1..$#r-1] ],
	     "column capture with first and last delimiters missing" );
};

subtest "round_to_length" => sub {
  my %N=(
	 '123456'     =>{ 1=>'#', 3=>'###', 4=>'####', 5=>'1e+05', 6=>'123456', 7=>'123456' },
	 '-123456'    =>{ 1=>'#', 3=>'###', 4=>'####', 5=>'#####', 6=>'-1e+05', 7=>'-123456', 8=>'-123456' },
	 '0.0000'     =>{ 1=>'0', 2=>' 0',  3=>'0.0',  4=>'0.00',  5=>'0.000',  6=>'0.0000',  7=>'0.0000'  },
	 '0'          =>{ 0=>'',  1=>'0',   2=>'0' },
	 '123456.789' =>{ 1=>'#', 3=>'###', 4=>'####', 5=>'1e+05', 6=>'123457', 7=>' 123457',
			  8=>'123456.8', 9=>'123456.79', 10=>'123456.789', 11=>'123456.789' },
	 '-123456.789'=>{ 1=>'#', 3=>'###', 4=>'####', 5=>'#####', 6=>'-1e+05', 7=>'-123457',
			  8=>' -123457', 9=>'-123456.8', 10=>'-123456.79', 11=>'-123456.789', 12=>'-123456.789' },
	 '0.001234'   =>{ 1=>'0', 2=>' 0',  3=>'0.0',  4=>'0.00',  5=>'0.001',
			  6=>'0.0012',  7=>'0.00123', 8=>'0.001234', 9=>'0.001234' },
	 '-0.001234'  =>{ 1=>'#', 2=>'-0',  3=>' -0',  4=>'-0.0',  5=>'-0.00',
			  6=>'-0.001',  7=>'-0.0012', 8=>'-0.00123', 9=>'-0.001234', 10=>'-0.001234' },
	 '0.0001234'  =>{ 1=>'0', 2=>' 0',  3=>'0.0',  4=>'0.00',  5=>'1e-04',
			  6=>'0.0001',  7=>'0.00012', 8=>'0.000123', 9=>'0.0001234', 10=>'0.0001234' },
	 '-0.0001234' =>{ 1=>'#', 2=>'-0',  3=>' -0',  4=>'-0.0',  5=>'-0.00',
			  6=>'-1e-04',  7=>'-0.0001', 8=>'-0.00012', 9=>'-0.000123', 10=>'-0.0001234', 11=>'-0.0001234' },
	 '0.00001234' =>{ 1=>'0', 2=>' 0',  3=>'0.0',  4=>'0.00',  5=>'1e-05',
			  6=>' 1e-05',  7=>'1.2e-05', 8=>'1.23e-05', 9=>'1.234e-05', 10=>'0.00001234' },
	 '-0.00001234'=>{ 1=>'#', 2=>'-0',  3=>' -0',  4=>'-0.0',  5=>'-0.00',
			  6=>'-1e-05',  7=>' -1e-05', 8=>'-1.2e-05', 9=>'-1.23e-05', 10=>'-1.234e-05', 11=>'-0.00001234' }
	);
  for my $n (keys %N) {
    is( IPAC_AsciiTable::round_to_length($n,$_), $N{$n}{$_}, "round_to_length of $n to $_ digit(s)" ) for sort { $a<=>$b } keys %{$N{$n}}
  }
};

subtest "pad_to_length" => sub {
  my %P=(
	 'abc'   => { 0=>'abc', 3=>'abc', 4=>' abc' },
	 ''      => { 0=>'',    1=>' ' },
	 ' '     => { 0=>' ',   1=>' ', 2=>'  ' }
	);
  for my $p (keys %P) {
    is( IPAC_AsciiTable::pad_to_length($p,$_), $P{$p}{$_}, "pad_to_length on $p to $_ chars" ) for sort { $a<=>$b } keys %{$P{$p}}
  }
};

subtest "_output_row" => sub {
  is( IPAC_AsciiTable::_output_row([(1.0,2.0,3.0)],      [0,2,4,6],  '@'), '@1@2@3@',          "_output_row on single digits" );
  is( IPAC_AsciiTable::_output_row([(1.111,2.222,7.777)],[0,5,10,15],'|'), '|1.11|2.22|7.78|', "_output_row on truncated numbers" );
  is( IPAC_AsciiTable::_output_row([('abcdefg','')],     [0,5,10,15],'|'), '|abcd|    |    |', "_output_row on truncated and missing alpha" );
};

subtest "empty table" => sub {
  my $A1=new IPAC_AsciiTable;
  isa_ok( $A1, 'IPAC_AsciiTable', "Empty Table created via new file" );
  my $A2=new_empty IPAC_AsciiTable;
  isa_ok( $A2, 'IPAC_AsciiTable', "Empty Table created via new_empty" );
  
  is_deeply( $A1, $A2, "two different versions of empty constructor agree" );
  
  is( $A1->n_cols(),      0,     "Empty table has no columns" );
  is( $A1->col(''),       undef, "Column-name not found returns undef" );
  is( $A1->col_name(0),   undef, "First column name is undefined for empty table" );
  is( $A1->n_data_rows(), 0,     "Empty table has no data rows" );
  is( $A1->col_number(''),undef, "Missing column name returns undef" );
  is( $A1->row(0),        undef, "row 0 from empty table returns undef" );
  
  is_deeply( $A1->extract(''), { ''=>[ undef ] }, "extract on missing column return undef array element" );

  my $tf=basename($0)."-$$-temp.tbl";
  lives_ok( sub { $A1->write_to_file($tf) }, "Write an empty table to file $tf" ) or diag explain $A1;
  
  my $A3=new IPAC_AsciiTable($tf);
  isa_ok( $A3, 'IPAC_AsciiTable', "Table created via new file with $tf" );

  my $A4=new_from_file IPAC_AsciiTable $tf;
  isa_ok( $A4, 'IPAC_AsciiTable', "Table created via new_from_file with $tf" );
  is_deeply( $A3, $A4, "two different versions of constructor_from_file agree -- for empty file" );

  lives_ok( sub { unlink $tf }, "done with temporary file $tf" );
};

subtest "IRSA Sample Table" => sub {
  my $tf=basename($0)."-$$-temp.tbl";
  getstore('http://irsa.ipac.caltech.edu/applications/DDGEN/Doc/sample.tbl',$tf);
  my @row_data=qw( 165.466279 -34.704730 5 11.27 K6Ve );
  my @cn=qw(ra dec n_obs V SpType );
  my %p=( catalog=>'Sample Catalog' );
  my $A=new_from_file IPAC_AsciiTable $tf;
  isa_ok( $A, 'IPAC_AsciiTable', "Sample Table from IRSA via $tf" );
  is_deeply( [ sort { $a cmp $b } $A->parm_list() ], [ sort { $a cmp $b } keys %p ], "List of parameters" );
  for ($A->parm_list()) { is( $A->parm_value($_), $p{$_}, "value of parameter $_" ) }
  is( $A->n_data_rows(), 1, "number of data rows" );
  is( $A->n_cols(),      5, "number of columns" );
  is_deeply( [$A->row(0) ], [ @row_data ], "first data row" );
  for (0..$#cn) { is( $A->col_number($cn[$_]), $_, "Column $_ name is $cn[$_]" ) }
  for (0..$#cn) { is( $A->col_name($_), $cn[$_],   "column name $cn[$_] for col num $_" ) }
  for (0..$#cn) { is_deeply( [ $A->col($cn[$_]) ], [ $row_data[$_] ], "column $cn[$_]" ) }
  lives_ok( sub { unlink $tf }, "done with temporary file $tf" );
};

subtest "2MASS Sample Table" => sub {
  my $tf=basename($0)."-$$-temp.tbl";
  getstore('http://irsa.ipac.caltech.edu/applications/DDGEN/Doc/test2.tbl',$tf);
  my @row_data=qw( 10.684737 41.269035 0.08 0.07 87 00424433+4116085 9.453 0.051 0.052 5385.6 
		   8.668 0.050 0.051 5089.9 8.475 0.050 0.051 3684.8 EEE 222 111 000 556655 2 0 );
  my $col_name="|        ra|       dec|err_maj|err_min|err_ang|      designation|   j_m|j_cmsig|j_msigcom|"
    ."     j_snr|   h_m|h_cmsig|h_msigcom|     h_snr|   k_m|k_cmsig|k_msigcom|     k_snr|ph_qual|rd_flg|bl_flg|cc_flg|"
    ."  ndet|gal_contam|mp_flg|";
  $col_name=~s/[|]/ /g;
  my @cn=split(' ',tw($col_name));
  my %p=(
	 fixlen        => 'T',
	 primary       => 0,
	 RowsRetreived => 1, 
	 QueryTime     => '00:00:24.86043',
	 ORIGIN        => 'IPAC Infrared Science Archive (IRSA), Caltech/JPL',
	 DATETIME      => '2003-09-04 16:05:22',
	 DATABASE      => '2MASS All-Sky Point Source Catalog (PSC) (fp_psc)',
	 EQUINOX       => 'J2000',
	 SKYAREA       => 'within 2 arcsec radius of ra=10.68469 dec=+41.26904 Eq J2000 ',
	 #	 SQL           => 'WHERE ',
	 SQL           => 'SELECT (25 column names follow in next row.)'
	);
  is( scalar(@row_data), scalar(@cn), "2MASS sample ref data is self-consistent for testing" );
  my $A=new_from_file IPAC_AsciiTable $tf;
  isa_ok( $A, 'IPAC_AsciiTable', "Sample Table from IRSA via $tf" );
  is_deeply( [ sort { $a cmp $b } $A->parm_list() ], [ sort { $a cmp $b } keys %p ], "List of parameters" );
  for ($A->parm_list()) { is( $A->parm_value($_), $p{$_}, "value of parameter $_" ) }
  is( $A->n_data_rows(),    1,                 "number of data rows in IRSA sample table" );
  is( $A->n_cols(),         scalar(@row_data), "number of columns in IRSA sample table" );
  is_deeply( [$A->row(0) ], [ @row_data ],     "data row from IRSA sample table" );
  for (0..$#cn) { is( $A->col_number($cn[$_]), $_, "IRSA sample table Column $_ name is $cn[$_]" ) }
  for (0..$#cn) { is( $A->col_name($_), $cn[$_],   "IRSA sample table column name $cn[$_] for col num $_" ) }
  for (0..$#cn) { is_deeply( [ $A->col($cn[$_]) ], [ $row_data[$_] ], "IRSA Sample table column $cn[$_]" ) }
  lives_ok( sub { unlink $tf }, "done with temporary file $tf" );
};

done_testing;

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
