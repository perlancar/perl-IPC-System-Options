#!perl

use strict;
use warnings;
use Test::Exception;
use Test::More 0.98;

use Cwd;
use File::Temp qw(tempfile tempdir);
use IPC::System::Options qw(system readpipe run);

subtest system => sub {
    subtest "opt:die" => sub {
        lives_ok { system(rand()) };
        dies_ok { system({die=>1}, rand()) };
    };
};

subtest readpipe => sub {
    ok 1;
};

subtest run => sub {
    ok 1;
};

done_testing;
