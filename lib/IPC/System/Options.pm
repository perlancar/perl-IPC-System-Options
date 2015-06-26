package IPC::System::Options;

# DATE
# VERSION

use strict;
use warnings;

use Carp;
use Proc::ChildError qw(explain_child_error);

my $log;
our %Global_Opts;

sub import {
    my $self = shift;

    my $caller = caller();
    my $i = 0;
    while ($i < @_) {
        if ($_[$i] eq 'system' || $_[$i] eq 'backtick' || $_[$i] eq 'import') {
            no strict 'refs';
            *{"$caller\::$_[$i]"} = \&{$_[$i]};
        } elsif ($_[$i] =~ /\A-(.+)/) {
            croak "$_[$i] requires an argument" unless $i < @_-1;
            $Global_Opts{$1} = $_[$i+1];
            $i++;
        } else {
            croak "$_[$i] is not exported by ".__PACKAGE__;
        }
        $i++;
    }
}

sub _system_or_backtick {
    my $which = shift;
    my $opts = ref($_[0]) eq 'HASH' ? shift : {};
    for (keys %Global_Opts) {
        $opts->{$_} = $Global_Opts{$_} if !defined($opts->{$_});
    }
    my @args = @_;

    my $opt_die = $opts->{die} || $opts->{dies};

    # set ENV
    my %save_env;
    my %set_env;
    if ($opts->{lang}) {
        $set_env{LC_ALL}   = $opts->{lang};
        $set_env{LANGUAGE} = $opts->{lang};
        $set_env{LANG}     = $opts->{lang};
    }
    if ($opts->{env}) {
        $set_env{$_} = $opts->{env}{$_} for keys %{ $opts->{env} };
    }
    if (%set_env) {
        for (keys %set_env) {
            $save_env{$_} = $ENV{$_};
            $ENV{$_} = $set_env{$_};
        }
    }
    if ($opts->{capture}) {
        die "Please provide arrayref for capture"
            unless ref($opts->{capture}) eq 'ARRAY';
    }

    $log ||= do { require Log::Any; Log::Any->get_logger } if $opts->{log};

    my $wa;
    my $res;
    my $exit_code;
    my $os_error;

    if ($which eq 'system') {

        $log->tracef("system(%s), env=%s", \@args, \%set_env) if $opts->{log};
        my $doit = sub {
            if ($opts->{shell}) {
                # force the use of shell
                $res = system join(" ", @args);
            } elsif (defined $opts->{shell}) {
                # forbid shell
                $res = system {$args[0]} @args;
            } else {
                # might or might not use shell (if @args == 1)
                $res = system @args;
            }
            $exit_code = $?;
            $os_error = $!;
        };
        if ($opts->{capture}) {
            require Capture::Tiny;
            ($opts->{capture}[0], $opts->{capture}[1]) =
                &Capture::Tiny::capture($doit);
        } else {
            $doit->();
        }

    } else {

        $wa = wantarray;
        my $cmd = join " ", @args;
        $log->tracef("qx(%s), env=%s", $cmd, \%set_env) if $opts->{log};
        my $doit = sub {
            if ($wa) {
                $res = [`$cmd`];
            } else {
                $res = `$cmd`;
            }
            $exit_code = $?;
            $os_error = $!;
        };
        if ($opts->{capture}) {
            require Capture::Tiny;
            ($opts->{capture}[0], $opts->{capture}[1]) =
                &Capture::Tiny::capture($doit);
        } else {
            $doit->();
        }

        # log output
        if ($opts->{log}) {
            my $res_show;
            if (defined $opts->{max_log_output}) {
                $res_show = '';
                if ($wa) {
                    for (@$res) {
                        if (length($res_show) + length($_) >=
                                $opts->{max_log_output}) {
                            $res_show .= substr(
                                $_,0,$opts->{max_log_output}-length($res_show));
                            last;
                        } else {
                            $res_show .= $_;
                        }
                    }
                } else {
                    if (length($res) > $opts->{max_log_output}) {
                        $res_show = substr($res, 0, $opts->{max_log_output});
                    }
                }
            }
            $log->tracef("result of backtick(): %s (%d bytes)",
                         defined($res_show) ? $res_show : $res,
                         defined($res_show) ?
                             $opts->{max_log_output} : length($res))
                unless $exit_code;
        }

    } # which

    # restore ENV
    if (%save_env) {
        for (keys %save_env) {
            if (defined $save_env{$_}) {
                $ENV{$_} = $save_env{$_};
            } else {
                undef $ENV{$_};
            }
        }
    }

    if ($exit_code) {
        $log->errorf("%s(%s) failed: %d (%s)",
                     $which, \@args, $exit_code,
                     explain_child_error($exit_code, $os_error))
            if $opts->{log};
        croak "$which(".join(" ", @args).") failed: " .
            explain_child_error($exit_code, $os_error) if $opt_die;
    }

    # make sure our user see the correct exit code & os error. this is not
    # currently needed as nothing yet clobbers $? & $!. but they might be needed
    # later (if we do more stuff which sets these variables) so i put it in.
    $? = $exit_code;
    $! = $os_error;

    return $wa ? @$res : $res;
}

sub system {
    _system_or_backtick('system', @_);
}

sub backtick {
    _system_or_backtick('backtick', @_);
}

1;
# ABSTRACT: Perl's system() and backtick/qx replacement/wrapper, with options

=head1 SYNOPSIS

 use IPC::System::Options qw(system backtick);

 # use exactly like system()
 system(...);

 # use exactly like backtick (qx, ``)
 my $res = backtick(...);

 # but it accepts an optional hash first argument to specify options
 system({...}, ...);

 # run without shell, even though there is only one argument
 system({shell=>0}, "ls");
 system({shell=>0}, "ls -lR"); # will fail, as there is no 'ls -lR' binary

 # set LC_ALL/LANGUAGE/LANG environment variable
 system({lang=>"de_DE.UTF-8"}, "df");

 # log using Log::Any, die on failure
 system({log=>1, die=>1}, "blah", ...);

Set default options for all calls (prefix each option with dash):

 use IPC::System::Options 'system', 'backtick', -log=>1, -die=>1;


=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 system([ \%opts ], @args)

Just like perl's C<system()> except that it accepts an optional hash first
argument to specify options. Currently known options:

=over

=item * shell => bool

Can be set to 0 to always avoid invoking the shell. The default is to use the
shell under certain conditions, like Perl's C<system()>.

=item * lang => str

Temporarily set locale-related environment variables: C<LC_ALL> (this is the
highest precedence, even higher than the other C<LC_*> variables including
C<LC_MESSAGES>), C<LANGUAGE> (this is used in Linux, with precedence higher than
C<LANG> but lower than C<LC_*>), and C<LANG>.

Of course you can set the environment variables manually (or use the C<env>
option), this option is just for convenience.

=item * env => hashref

Temporarily set environment variables.

=item * log => bool

If set to true, then will log invocation as well as return/result value. Will
log using L<Log::Any> at the C<trace> level.

=item * die => bool

If set to true, will die on failure.

=item * capture => arrayref

Capture output (stdout/stderr) using L<Capture::Tiny>. The first element of the
arrayref will contain stdout, the second will contain stderr.

=back

=head2 backtick([ \%opts ], @args)

Just like perl's backtick operator (C<qx()>) except that it accepts an optional
hash first argument to specify options.

Known options:

=over

=item * lang => str

See option documentation in C<system()>.

=item * env => hash

See option documentation in C<system()>.

=item * log => bool

See option documentation in C<system()>.

=item * die => bool

See option documentation in C<system()>.

=item * max_log_output => int

If set, will limit result length being logged. It's a good idea to set this
(e.g. to 1024) if you expect some command to return large output.

=back
