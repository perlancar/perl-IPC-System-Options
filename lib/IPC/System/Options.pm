package IPC::System::Options;

# DATE
# VERSION

use strict;
use warnings;

use Proc::ChildError qw(explain_child_error);
use String::ShellQuote;

my $log;
our %Global_Opts;

sub import {
    my $self = shift;

    my $caller = caller();
    my $i = 0;
    while ($i < @_) {
        # backtick is the older, deprecated name for readpipe
        if ($_[$i] =~ /\A(system|readpipe|backtick|run|import)\z/) {
            no strict 'refs';
            *{"$caller\::$_[$i]"} = \&{"$self\::" . $_[$i]};
        } elsif ($_[$i] =~ /\A-(.+)/) {
            die "$_[$i] requires an argument" unless $i < @_-1;
            $Global_Opts{$1} = $_[$i+1];
            $i++;
        } else {
            die "$_[$i] is not exported by ".__PACKAGE__;
        }
        $i++;
    }
}

sub _quote {
    if (@_ == 1) {
        return $_[0];
    }

    if ($^O eq 'MSWin32') {
        require Win32::ShellQuote;
        return Win32::ShellQuote::quote_system_string(@_);
    } else {
        return shell_quote(@_);
    }
}

sub _system_or_readpipe_or_run {
    my $which = shift;
    my $opts = ref($_[0]) eq 'HASH' ? shift : {};
    for (keys %Global_Opts) {
        $opts->{$_} = $Global_Opts{$_} if !defined($opts->{$_});
    }
    my @args = @_;

    # check known options
    for (keys %$opts) {
        die "Unknown option '$_'"
            unless /\A(
                        capture_stdout|capture_stderr|
                        chdir|dies?|env|lang|log||max_log_output|shell|
                        stdin # XXX: only for run()
                    )\z/x;
    }

    my $opt_die = $opts->{die} || $opts->{dies};

    my $exit_code;
    my $os_error = "";
    my $extra_error;

    $log ||= do { require Log::Any::IfLOG; Log::Any::IfLOG->get_logger } if $opts->{log};

    my $cwd;
    if ($opts->{chdir}) {
        require Cwd;
        $cwd = Cwd::getcwd();
        if (!defined $cwd) { # checking $! is always true here, why?
            $log->error("Can't getcwd: $!") if $log;
            $exit_code = -1;
            $os_error = $!;
            $extra_error = "Can't getcwd";
            goto CHECK_RESULT;
        }
        unless (chdir $opts->{chdir}) {
            $log->error("Can't chdir to '$opts->{chdir}': $!") if $log;
            $exit_code = -1;
            $os_error = $!;
            $extra_error = "Can't chdir";
            goto CHECK_RESULT;
        }
    }

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

    my $wa;
    my $res;

    my $code_capture = sub {
        my $doit = shift;

        if ($opts->{capture_stdout} && $opts->{capture_stderr}) {
            require Capture::Tiny;
            (${ $opts->{capture_stdout} }, ${ $opts->{capture_stderr} }) =
                &Capture::Tiny::capture($doit);
        } elsif ($opts->{capture_stdout}) {
            require Capture::Tiny;
            ${ $opts->{capture_stdout} } =
                &Capture::Tiny::capture_stdout($doit);
        } elsif ($opts->{capture_stderr}) {
            require Capture::Tiny;
            ${ $opts->{capture_stderr} } =
                &Capture::Tiny::capture_stderr($doit);
        } else {
            $doit->();
        }
    };

    if ($which eq 'system') {

        $log->tracef("system(%s), env=%s", \@args, \%set_env) if $opts->{log};
        my $doit = sub {
            if ($opts->{shell}) {
                # force the use of shell
                $res = system _quote(@args);
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
        $code_capture->($doit);

    } elsif ($which eq 'readpipe') {

        $wa = wantarray;
        my $cmd = _quote(@args);
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
        $code_capture->($doit);

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
            $log->tracef("result of readpipe(): %s (%d bytes)",
                         defined($res_show) ? $res_show : $res,
                         defined($res_show) ?
                             $opts->{max_log_output} : length($res))
                unless $exit_code;
        }

    } else {

        $log->tracef("run(%s), env=%s", \@args, \%set_env) if $opts->{log};
        require IPC::Run;
        $res = IPC::Run::run(
            \@args,
            defined($opts->{stdin}) ? \$opts->{stdin} : \*STDIN,
            sub {
                if ($opts->{capture_stdout}) {
                    ${$opts->{capture_stdout}} .= $_[0];
                } else {
                    print $_[0];
                }
            }, # out
            sub {
                if ($opts->{capture_stderr}) {
                    ${$opts->{capture_stderr}} .= $_[0];
                } else {
                    print STDERR $_[0];
                }
            }, # err
        );
        $exit_code = $?;
        $os_error = $!;

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

    # restore previous working directory
    if ($cwd) {
        unless (chdir $cwd) {
            $log->error("Can't chdir back to '$cwd': $!") if $log;
            $exit_code ||= -1;
            $os_error = $!;
            $extra_error = "Can't chdir back";
            goto CHECK_RESULT;
        }
    }

  CHECK_RESULT:
    if ($exit_code) {
        if ($opts->{log} || $opt_die) {
            my $msg = sprintf(
                "%s(%s) failed: %s (%s)%s%s",
                $which,
                join(" ", @args),
                defined $extra_error ? "" : $exit_code,
                defined $extra_error ? "$extra_error: $os_error" : explain_child_error($exit_code, $os_error),
                (ref($opts->{capture_stdout}) ?
                     ", captured stdout: <<" .
                     (defined ${$opts->{capture_stdout}} ? ${$opts->{capture_stdout}} : ''). ">>" : ""),
                (ref($opts->{capture_stderr}) ?
                     ", captured stderr: <<" .
                     (defined ${$opts->{capture_stderr}} ? ${$opts->{capture_stderr}} : ''). ">>" : ""),
            );
            $log->error($msg) if $opts->{log};
            die $msg if $opt_die;
        }
    }

    $? = $exit_code;

    return $wa && $which ne 'run' ? @$res : $res;
}

sub system {
    _system_or_readpipe_or_run('system', @_);
}

# backtick is the older, deprecated name for readpipe
sub backtick {
    _system_or_readpipe_or_run('readpipe', @_);
}

sub readpipe {
    _system_or_readpipe_or_run('readpipe', @_);
}

sub run {
    _system_or_readpipe_or_run('run', @_);
}

1;
# ABSTRACT: Perl's system() and readpipe/qx replacement, with options

=for Pod::Coverage ^(backtick)$

=head1 SYNOPSIS

 use IPC::System::Options qw(system readpipe run);

 # use exactly like system()
 system(...);

 # use exactly like readpipe() (a.k.a. qx a.k.a. `` a.k.a. the backtick operator)
 my $res = readpipe(...);
 $res = `...`;

 # but these functions accept an optional hash first argument to specify options
 system({...}, ...);
 readpipe({...}, ...);

 # run without shell, even though there is only one argument
 system({shell=>0}, "ls");
 system({shell=>0}, "ls -lR"); # will fail, as there is no 'ls -lR' binary

 # force shell, even though there are multiple arguments (arguments will be
 # quoted for you, including proper quoting on Win32)
 system({shell=>1}, "ls", "-lR");

 # set LC_ALL/LANGUAGE/LANG environment variable
 $res = readpipe({lang=>"de_DE.UTF-8"}, "df");

 # log using Log::Any, die on failure
 system({log=>1, die=>1}, "blah", ...);

 # chdir first before running program (and chdir back afterwards)
 system({chdir => "/tmp", die => 1}, "some-program");

Set default options for all calls (prefix each option with dash):

 use IPC::System::Options 'system', 'readpipe', -log=>1, -die=>1;

C<run()> is like C<system()> but uses L<IPC::Run>'s C<run()> instead of
C<system()>:

 run('ls');

 # also accepts an optional hash first argument. some additional options that
 # run() accepts: stdin.
 run({capture_stdout => \$stdout, capture_stderr => \$stderr}, 'ls', '-l');


=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 system([ \%opts ], @args)

Just like perl's C<system()> except that it accepts an optional hash first
argument to specify options. Currently known options:

=over

=item * shell => bool

Can be set to 0 to always avoid invoking the shell. The default is to use the
shell under certain conditions, like perl's C<system()>. But unlike perl's
C<system()>, you can force shell usage even though you pass multiple arguments
(in which case, the arguments will be quoted for you, including proper quoting
on Win32).

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

=item * capture_stdout => scalarref

Capture stdout using L<Capture::Tiny>.

=item * capture_stderr => scalarref

Capture stderr using L<Capture::Tiny>.

=item * chdir => str

Attempt to change to specified directory first and change back to the original
directory after the command has been run. This is a convenient option so you can
do this kind of task in a single call:

 {
     my $cwd = getcwd();
     chdir $dir or die;
     system(...);
     chdir $cwd or die;
 }

If the attempt to chdir before command execution fails, will die if C<die>
option is set to true. Otherwise, C<$!> (OS error) will be set to the C<chdir()>
error and to minimize surprise C<$?> (child exit code) will also be set to
non-zero value (-1) even though at this point no child process has been run.

If the attempt to chdir back (after command execution) fails, will die if C<die>
option is set to true. Otherwise, C<$!> will be set to the C<chdir()> error and
C<$?> will be set to -1 only if C<$?> is zero. So if the command fails, C<$?>
will contain the exit code of the command.

=back

=head2 readpipe([ \%opts ], @args)

Just like perl's C<readpipe()> (a.k.a. C<qx()> a.k.a. C<``> a.k.a. the backtick
operator) except that it accepts an optional hash first argument to specify
options. And it can accept multiple arguments (in which case, the arguments will
be quoted for you, including proper quoting on Win32).

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

=item * capture_stdout => scalarref

See option documentation in C<system()>.

=item * capture_stderr => scalarref

See option documentation in C<system()>.

=item * max_log_output => int

If set, will limit result length being logged. It's a good idea to set this
(e.g. to 1024) if you expect some command to return large output.

=item * chdir => str

See option documentation in C<system()>.

=back

=head2 run([ \%opts ], @args)

Like C<system()>, but uses L<IPC::Run>'s C<run()>. Known options:

=over

=item * lang => str

See option documentation in C<system()>.

=item * env => hash

See option documentation in C<system()>.

=item * log => bool

See option documentation in C<system()>.

=item * die => bool

See option documentation in C<system()>.

=item * capture_stdout => scalarref

See option documentation in C<system()>.

=item * capture_stderr => scalarref

See option documentation in C<system()>.

=item * stdin => scalar

Supply standard input.

=item * chdir => str

See option documentation in C<system()>.

=back
