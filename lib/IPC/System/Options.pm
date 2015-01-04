package IPC::System::Options;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(system backtick);

sub _system_or_backtick {
    my $which = shift;
    my $opts = ref($_[0]) eq 'HASH' ? shift : {};

    local $ENV{LC_ALL}   = $opts->{lang} if $opts->{lang};
    local $ENV{LANGUAGE} = $opts->{lang} if $opts->{lang};
    local $ENV{LANG}     = $opts->{lang} if $opts->{lang};

    if ($which eq 'system') {
        if (defined($opts->{shell}) && !$opts->{shell}) {
            return system {$_[0]} @_;
        } else {
            return system @_;
        }
    } else {
        my $cmd = join " ", @_;
        return `$cmd`;
    }
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

 use IPC::System::Options qw(system);

 # use exactly like system()
 system(...);

 # but it accepts an optional hash first argument to specify options
 system({...}, ...);

 # run without shell, even though there is only one argument
 system({shell=>0}, "ls");
 system({shell=>0}, "ls -lR"); # will fail, as there is no 'ls -lR' binary

 # set LC_ALL/LANGUAGE/LANG environment variable
 system({lang=>"de_DE.UTF-8"}, "df");


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

Set locale-related environment variables: C<LC_ALL> (this is the highest
precedence, even higher than the other C<LC_*> variables including
C<LC_MESSAGES>), C<LANGUAGE> (this is used in Linux, with precedence higher than
C<LANG> but lower than C<LC_*>), and C<LANG>.

Of course you can set the environment variables manually, this option is just
for convenience.

=head2 backtick([ \%opts ], @args)

Just like perl's backtick operator (C<qx()>) except that it accepts an optional
hash first argument to specify options.

Known options:

=over

=item * lang => str

See option documentation in C<system()>.

=back
