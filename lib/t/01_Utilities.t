#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

=head1 Name - 01_Utilities.t

Execute tests for the Utilities.pm module.

=head1 Synopsis

  ./01_Utilities.t

The paths are set up for executing the tests within the folder
where the scripts are.

=cut

BEGIN { use lib '..'; use_ok('Utilities', qw( pi tw nw max uniq identical_arrays is_number
					      fmod deg_to_hhmmss deg_to_ddmmss ra_str dec_str )) }

sub equal_numeric_arrays {
    my $a=shift;
    my $b=shift;
    my $t=shift;
    my $EPS=1.0e-6;
    unless (scalar(@$a)==scalar(@$b)) {
	fail "$t - array sizes differ:  ".scalar(@$a).' vs '.scalar(@$a);
	diag explain $a;
	diag explain $b;
	return 0;
    }
    for my $i (0..$#{$a}) {
	next if $a->[$i]==$b->[$i];
	next if abs($a->[$i]-$b->[$i])<$EPS;
	fail "$t - arrays differ in element $i:  $a->[$i] vs $b->[$i]";
	diag explain $a;
	diag explain $b;
	return 0;
    }
    pass $t;
    return 1;
}

is( pi(), 4.0*atan2(1.0,1.0), 'PI constant set correctly' );

my $PI=pi();

is( tw('  test string  '   ),'test string',  'tw removes leading and trailing space but keeps internal space' );
is( nw('  test string  '   ),'teststring',   'nw removes all space' );
is( tw("\ntest\tstring\t"  ),"test\tstring", 'tw removes "outside" cr and tabs, too' );
is( nw("\ttest\t\nstring\n"),"teststring",   'nw removes internal and external cr and tabs as well' );

is( max( 2,3,4,5,6 ),             6, "max on argument list" );
is( max( [2,3,4,5,6] ),           6, "max on anonymous array" );
is( max( 2,2,2 ),                 2, "max on list of flat values" );
dies_ok { max( \$PI ) }              "max does not allow ref to scalar argument";
dies_ok { max( { a=>3 } ) }          "max does not allow ref to hash argument";
is( max( $PI,$PI ), $PI, "two scalar arguments ok for max" );

my @test = (qw( a b c b d a b c e d f ));
is_deeply( [ sort { $a cmp $b } uniq(@test) ], [qw( a b c d e f )], 'uniq removes duplicate items' );

is( identical_arrays( @test,  @test),               1, "same array is identical to itself" );
is( identical_arrays(\@test, \@test),               1, "same refarray is identical to itself" );
is( identical_arrays(\@test,  @test),               1, "refarray is identical to array" );
is( identical_arrays( @test, \@test),               1, "same array is identical to itself as refarray" );
is( identical_arrays( [],     [] ),                 1, "empty arrays are identical" );
is( identical_arrays( @test,  [] ),                 0, "non-empty array not identical to empty array" );
is( identical_arrays(\@test,  [] ),                 0, "non-empty refarray not identical to empty array" );
is( identical_arrays( [],    \@test ),              0, "non-empty array not identical to empty refarray" );
is( identical_arrays( @test,  [@test,'b'] ),        0, "almost identical arrays with one extra element are not identical" );
is( identical_arrays( @test,  [pop @test, @test] ), 0, "re-arranged non-identical arrays not identical" );

dies_ok { identical_arrays( @test, () ) }  "two array arguments or refs for identical_arrays:  check second";
dies_ok { identical_arrays( (), @test ) }  "two array arguments or refs for identical_arrays:  check first";
dies_ok { identical_arrays( [], () ) }     "two array arguments or refs for identical_arrays:  check both";
dies_ok { identical_arrays(  $PI,  $PI ) } "identical_arrays does not allow scalar arguments";
dies_ok { identical_arrays( \$PI, \$PI ) } "identical_arrays does not allow ref to scalar arguments";


is( fmod(5.5 ,  3.0), 2.5, 'fmod on a real value over the modulus' );
is( fmod(2.5 ,  3.0), 2.5, 'fmod on a real value under the modulus');
is( fmod(0.0 ,  3.0), 0.0, 'fmod on zero' );
is( fmod(-0.5,  3.0), 2.5, 'fmod on negative value under the modulus' );
is( fmod(-4.0,  3.0), 2.0, 'fmod on negative value over the modulus'  );

# all the numbers should be the same with a negative modulus
is( fmod(5.5 , -3.0), 2.5, 'fmod on a real value over the negative modulus' );
is( fmod(2.5 , -3.0), 2.5, 'fmod on a real value under the negative modulus');
is( fmod(0.0 , -3.0), 0.0, 'fmod on zero with negative modulus' );
is( fmod(-0.5, -3.0), 2.5, 'fmod on negative value under the negative modulus' );
is( fmod(-4.0, -3.0), 2.0, 'fmod on negative value over the negative modulus'  );

equal_numeric_arrays( [ deg_to_hhmmss( 90.0) ], [ ( 6,  0,  0.0) ],  'Conversion of  RA from DEG to HHMMSS' );
equal_numeric_arrays( [ deg_to_hhmmss(-90.0) ], [ (18,  0,  0.0) ],  'Conversion of -RA from DEG to HHMMSS' );
equal_numeric_arrays( [ deg_to_hhmmss(  7.5) ], [ ( 0, 30,  0.0 ) ], 'Convert fractional RA from DEG to HHMMMSS');
equal_numeric_arrays( [ deg_to_hhmmss(15.0/3600.00) ],  
		      [ ( 0,  0,  1.0 ) ], 'Convert one sec of RA from DEG to HHMMMSS');
equal_numeric_arrays( [ deg_to_hhmmss(-15.0/3600.00) ], 
		      [ (23, 59, 59.0 ) ], 'Convert -1 sec of RA from DEG to HHMMMSS');
equal_numeric_arrays( [ deg_to_ddmmss( 90.0) ], [ ( 90,  0,  0.0) ],  'Conversion of  DEC from DEG to DDMMSS' );
equal_numeric_arrays( [ deg_to_ddmmss(-90.0) ], [ (-90,  0,  0.0) ],  'Conversion of -DEC from DEG to DDMMSS' );
equal_numeric_arrays( [ deg_to_ddmmss(  7.5) ], [ (  7, 30,  0.0 ) ], 'Convert fractional DEC from DEG to DDMMMSS');
equal_numeric_arrays( [ deg_to_ddmmss( 1.0/3600.00) ],  
		      [ (  0,  0,  1.0 ) ], 'Convert  1 sec of DEC from DEG to DDMMMSS');
equal_numeric_arrays( [ deg_to_ddmmss(-1.0/3600.00) ],  		       
		      [ (  0,  0, -1.0 ) ], 'Convert -1 sec of DEC from DEG to DDMMMSS');
equal_numeric_arrays( [ deg_to_ddmmss(-1.0/60.00)   ],  		       
		      [ (  0, -1,  0.0 ) ], 'Convert -1 min of DEC from DEG to DDMMMSS');
equal_numeric_arrays( [ deg_to_ddmmss(-1.0/60.00-1.0/3600.0) ],  
		      [ (  0, -1, 1.0 ) ], 'Convert -1 min and 1 sec of DEC from DEG to DDMMMSS');
equal_numeric_arrays( [ deg_to_ddmmss(-1-1.0/60.00-1.0/3600.0) ],  
		      [ ( -1,  1, 1.0 ) ], 'Convert -1 deg, 1 min, 1 sec of DEC from DEG to DDMMMSS');
equal_numeric_arrays( [ deg_to_ddmmss(-1+1.0/3600.0) ],  
		      [ (  0, -59, 59.0 ) ], 'Convert -1 deg less 1 sec of DEC from DEG to DDMMMSS');

is( ra_str( 90.0),          "+6 00  0.00", 'Conversion of  RA from DEG to HHMMSS string' );
is( ra_str(-90.0),         "+18 00  0.00", 'Conversion of -RA from DEG to HHMMSS string' );
is( ra_str(  7.5),          "+0 30  0.00", 'Convert fractional RA from DEG to HHMMMSS string');
is( ra_str(15.0/3600.00),   "+0 00  1.00", 'Convert one sec of RA from DEG to HHMMMSS string');
is( ra_str(-15.0/3600.00), "+23 59 59.00", 'Convert -1 sec of RA from DEG to HHMMMSS string');
is( dec_str( 90.0),         "+90 00  0.00", 'Conversion of  DEC from DEG to DDMMSS' );
is( dec_str(-90.0),         "-90 00  0.00", 'Conversion of -DEC from DEG to DDMMSS' );
is( dec_str(  7.5),          "+7 30  0.00", 'Convert fractional DEC from DEG to DDMMMSS string');
is( dec_str( 1.0/3600.00),   "+0 00  1.00", 'Convert  1 sec of DEC from DEG to DDMMMSS string');
is( dec_str(-1.0/3600.00),   "-0 00  1.00", 'Convert -1 sec of DEC from DEG to DDMMMSS string');
is( dec_str(-1.0/60.00),    "-0 01  0.00", 'Convert -1 min of DEC from DEG to DDMMMSS string');
is( dec_str(-1.0/60.00-1.0/3600.0),  "-0 01  1.00", 'Convert -1 min +1 sec of DEC from DEG to DDMMMSS string');
is( dec_str(-1-1.0/60.00-1.0/3600.0),"-1 01  1.00", 'Convert -1 deg, 1 min, 1 sec of DEC from DEG to DDMMMSS string');
is( dec_str(-1+1.0/3600.0),  "-0 59 59.00", 'Convert -1 deg less 1 sec of DEC from DEG to DDMMMSS string');

ok( is_number(5),       'integer is a number' );
ok( is_number(-5),      'negative integer is a number' );
ok( is_number(5.5),     'positive real number is a number' );
ok( is_number(-5.5),    'negative real number is a number' );
ok( is_number(5.3e7),   'scientific notation is a number' );
ok( is_number(-5.3e7),  'scientific notation for negative number' );
ok( is_number(-5.3e-7), 'scientific notation for negative exponent' );

ok( !is_number('a'),      'letter is not a number' );
ok( is_number('a5'),      'embedded number in the string');
ok( is_number('-5.3e-7'), 'string version of scientific notation for negative exponent' );
ok( !is_number(''),       'empty string is not a number' );

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
