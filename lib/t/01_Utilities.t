#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

=head1 Name - 01_Utilities.t

Execute tests for the Utilities.pm module.

=head1 Synopsis

  ./01_Utilities.t

The paths are set up for executing the tests within the folder
where the scripts are.

=cut


BEGIN { use lib '..'; use_ok('Utilities') }

is( $::M_PI, 4.0*atan2(1.0,1.0), 'M_PI constant set correctly' );

is( ::tw('  test string  '   ),'test string',  'tw removes leading and trailing space but keeps internal space' );
is( ::nw('  test string  '   ),'teststring',   'nw removes all space' );
is( ::tw("\ntest\tstring\t"  ),"test\tstring", 'tw removes "outside" cr and tabs, too' );
is( ::nw("\ttest\t\nstring\n"),"teststring",   'nw removes internal and external cr and tabs as well' );

my @test = (qw( a b c b d a b c e d f ));
is_deeply( [ sort { $a cmp $b } ::uniq @test ], [qw( a b c d e f )], 'uniq removes duplicate items' );

my @test_indices=(5,0,1,3,6,2,7,4,9,8,10);
is_deeply( [ ::remap @test, @test_indices ], [qw( a a b b b c c d d e f )], 'remap an array' );

like( ::today(), qr/20\d{2}\/\d{2}\/\d{2}/, 'today() gives correct format' );

# not sure how to do a test on ::now()

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

is( ra_str(90.5),  '+6 30  0.00', 'Conversion from RA to HHMMSS' );
is( ra_str(-90.5), '-6 30  0.00', 'Conversion from neg RA to HHMMSS' );

is( dec_str(90.5),  '+90 30  0.00', 'Conversion from DEC to HHMMSS' );
is( dec_str(-90.5), '-90 30  0.00', 'Conversion from neg DEC to HHMMSS' );

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
