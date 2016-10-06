#!perl

use strict;
use warnings;
use Test::Exception;
use Test::More 0.98;

use Cwd;
use File::Temp qw(tempfile tempdir);
use IPC::System::Options qw(system readpipe run);

subtest system => sub {
    subtest "unknown option -> die" => sub {
        dies_ok { system({foo => 1}, $^X, "-e1") };
    };
    subtest "opt:die" => sub {
        lives_ok { system(rand()) };
        dies_ok { system({die=>1}, rand()) };
    };
    subtest "opt:chdir" => sub {
        my $tempdir = tempdir(CLEANUP => 1);
        lives_ok { system({die=>1, chdir=>$tempdir}, $^X, "-e1") };
        dies_ok  { system({die=>1, chdir=>"$tempdir/sub"}, $^X, "-e1") };
        # XXX test $? set to -1 if chdir fails
        # XXX test $? set to -1 (only if $? from command was zero) if chdir back fails
        # XXX test chdir back fails
    };
};

subtest readpipe => sub {
    ok 1;
};

subtest run => sub {
    ok 1;
};

done_testing;
