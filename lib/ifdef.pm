package ifdef;

# Make sure we have version info for this module
# Be strict from now on

$VERSION = '0.07';
use strict;

# The flag to take all =begin CAPITALS pod sections
# Flag: set to true to output all source to be output as diff to STDERR

my $ALL;
my $DIFF = $ENV{'IFDEF_DIFF'};

# Get the necessary modules

use IO::File ();

# Use a source filter for the initial script
# Status as returned by source filter
# Flag: whether we're inside a =begin section being activated
# Flag: whether we're inside any =pod section

use Filter::Util::Call ();
my $STATUS;
my $ACTIVATING;
my $INPOD;

# Flag: depth of conditionals
# Flags: state of each level
# Module -> filename conversion hash

my $DEPTH;
my @STATE;
my %IFDEF;

# Install an @INC handler that
#  Obtains the parameters (defining $path on the fly)
#  If there is a request to translate a module to a filename
#   Make sure the delimiters are ok
#   Return whatever we know of this module

unshift( @INC,sub {
    my ($ref,$filename,$path) = @_;
    unless (ref $ref) {
        $ref =~ s#/#::#;
        return $IFDEF{$ref};
    }

#  For all of the directories to checl
#   If we have a reference
#    Let that handle the require if we're not it

    foreach (@INC) {
        if (ref) {
            goto &$_ unless $_ eq $ref;

#   Elseif the file exists
#    Attempts to open the file and reloops if failed
#    Attempt to open a temporary file or dies if failed
#    Convert filename to module name again
#    Save path for this module (in case someone needs it later)

        } elsif (-f ($path = "$_/$filename")) {
            open( my $in,$path ) or next;
            my $out = IO::File->new_tmpfile
             or die "Failed to create temporry file for '$path': $!\n";
            $filename =~ s#/#::#;
            $IFDEF{$filename} = $path;

#    Make sure we have our own $_
#    While there are lines to be read
#     Process the line
#     Write the line to the temporary file
#    Close the input file
#    Make sure we have a clean slate from now

            local $_ = \my $foo;
            while (<$in>) {
                &oneline;
                print $out $_;
            }
            close $in;
            &reset;

#    Make sure we'll read from the start of the file
#    And return that handle

            $out->seek( 0,0 ) or die "Failed to seek: $!\n";
            return $out;
        }
    }

# Return nothing to indicate that the rest should be searched (which will fail)

    return;
} );

# Satisfy require

1;

#---------------------------------------------------------------------------
# process
#
# Process a string (consisting of many lines)
#
#  IN: 1 string to process
# OUT: 1 processed string (in place change if called in void context)

sub process {

# Get lines from the string
# Start with a clean slate
# Make sure we don't affect $_ outside
# Process all lines
# Close of activating section (e.g. when called by "load")
# Return the result if not in void context

    my @line = split m#(?<=$/)#,$_[0];
    &reset;
    local $_ = \my $foo;
    &oneline foreach @line;
    push @line,"}$/" if $ACTIVATING;
    return join( '',@line ) if defined wantarray;

# Set the result directly
# Hint to the compiler we're not returning anything (optimilization)

    $_[0] = join( '',@line );
    undef;
} #process

#---------------------------------------------------------------------------
# reset
#
# Reset all internal variables to a known state

sub reset { $ACTIVATING = $INPOD = $DEPTH = 0 } #reset

#---------------------------------------------------------------------------
# oneline
#
# Process one line in $_ in place

sub oneline {

# Let the world know if we should

    print STDERR "<$_" if $DIFF;

# If this is a pod marker
#  If we're going back to source
#   Close the scope if we were activating code
#   Reset all parameters

    if (m#^=(\w+)#){
        if ($1 eq 'cut') {
            $_ = $ACTIVATING ? "}$/" : $/;
            &reset;

#  Elseif we're at the start of possibly activating source
#   If this is a pod marker that seems to have our special meaning
#    If global activation or this specific one
#     Open new scope (possibly closing old one)
#     Set activating flag
#     Reset that we're inside normal pod flag

        } elsif ($1 eq 'begin') {
            if (m#^=begin\s+([A-Z_0-9]+)\b#) {
                if ($ALL or $ENV{$1}) {
                    $_ = $ACTIVATING ? "}{$/" : "{;$/";
                    $ACTIVATING = 1;
                    $INPOD = 0;

#    Else (not activating this time)
#     Close scope if we were activated already
#     Reset acticating flag
#     Set flag that we're inside normal pod now

                } else {
                    $_ = $ACTIVATING ? "}$/" : $/;
                    $ACTIVATING = 0;
                    $INPOD = 1;
                }

#   Else (normal begin of pod)
#    Lose the line
#    Set flag that we're inside normal pod now

            } else {
                $_ = $/;
                $INPOD = 1;
            }

#  Elseif we're at the end of a possible activating section
#   Close scope if we we're activating
#   Reset activating flag
#   Set flag that we're in normal pod now

        } elsif ($1 eq 'end') {
            $_ = $ACTIVATING ? "}$/" : $/;
            $ACTIVATING = 0;
            $INPOD = 1;

#  Else (any other pod directive)
#   Reset the line
#   Set flag that we're in normal pod now

        } else {
            $_ = $/;
            $INPOD = 1;
        }

# Elseif we're already inside normal pod
#  Lose the line

    } elsif ($INPOD) {
        $_ = $/;

# Elseif (inside code) and looks like a comment line that we need to handle
#  Make it a normal source line if we should

    } elsif (m/^#\s+([A-Z_0-9]+)\b/) {
         s/^#\s+(?:[A-Z_0-9]+)\b// if $ENV{$1};
    }

# Let the world know if we should

    print STDERR ">$_" if $DIFF;
} #oneline

#---------------------------------------------------------------------------

# Perl specific subroutines

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2..N keys to watch for

sub import {

# Warn if we're being called from source (unless it's from the test-suite)

    warn "The '".
          __PACKAGE__.
          "' pragma is not supposed to be called from source\n"
           if ((caller)[2]) and ($_[0] ne '_testing_' and !shift);

# Lose the class
# Initialize the ignored list
# Loop for all parameters
#  If it is the "all" flag
#   Set the all flag
#  Elsif it is the "selected" flag
#   Reset the all flag
#  Elsif it is all uppercase
#   Set the environment variable
#  Else
#   Add to ignored list
# List any ignored parameters

    shift;
    my @ignored;
    foreach (@_) {
        if (m#^:?all$#) {
            $ALL = 1;
        } elsif (m#^:?selected$#) {
            $ALL = 0;
        } elsif (/^[A-Z_0-9]+$/) {
            $ENV{$_} = 1;
        } else {
            push @ignored,$_;
        }
    }
    warn "Ignored parameters: @ignored\n" if @ignored;

# Make sure we start with a clean slate
# Add a filter for the caller script which
#  If there is a line
#   Process it
#  Returns the status, $_ is set with what we want to give back

    &reset;
    Filter::Util::Call::filter_add( sub {
        if (($STATUS = Filter::Util::Call::filter_read()) > 0) {
            &oneline;
        }
        $STATUS;
    } );
} #import

#---------------------------------------------------------------------------

__END__

=head1 NAME

ifdef - conditionally enable text within pod sections as code

=head1 SYNOPSIS

  export DEBUGGING=1
  perl -Mifdef yourscript.pl

 or:

  perl -Mifdef=VERBOSE yourscript.pl

 or:

  perl -Mifdef=all yourscript.pl

 with:

  ======= yourscript.pl ================================================

  # code that's always compiled and executed

  =begin DEBUGGING

  warn "Only compiled and executed when DEBUGGING or 'all' enabled\n"

  =begin VERBOSE

  warn "Only compiled and executed when VERBOSE or 'all' enabled\n"

  =cut

  # code that's always compiled and executed

  # BEGINNING compiled and executed when BEGINNING enabled

  ======================================================================

=head1 DESCRIPTION

The "ifdef" pragma allows a developer to add sections of code that will be
compiled and executed only when the "ifdef" pragma is specifically enabled.
If the "ifdef" pragma is not enabled, then there is B<no> overhead involved
in either compilation of execution (other than the standard overhead of Perl
skipping =pod sections).

To prevent interference with other pod handlers, the name of the pod handler
B<must> be in uppercase.

If a =begin pod section is considered for replacement, then a scope is
created around that pod section so that there is no interference with any
of the code around it.  For example:

 my $foo = 2;

 =begin DEBUGGING

 my $foo = 1;
 warn "debug foo = $foo\n";

 =cut

 warn "normal foo = $foo\n";

is converted on the fly (before Perl compiles it) to:

 my $foo = 2;

 {

 my $foo = 1;
 warn "foo = $foo\n";

 }

 warn "normal foo = $foo\n";

But of course, this happens B<only> if the "ifdef" pragma is loaded B<and>
the environment variable B<DEBUGGING> is set.

As a shortcut for only single lines of code, you can also specify a single
line of code inside a commented line:

 # DEBUGGING print "we're in debugging mode now\n";

will only print the string "we're in debugging mode now\n" when the environment
variable B<DEBUGGING> is set.  Please note that the 'all' flag is ignored in
this case, as there is too much standard code out there that uses all uppercase
markers at the beginning of an inline comment which cause compile errors if
they would be enabled.

=head1 WHY?

One day, I finally had enough of always putting in and taking out debug
statements from modules I was developing.  I figured there had to be a
better way to do this.  Now, this module allows to leave debugging code
inside your programs and only have them come alive when I<you> want them
to be alive.  I<Without any run-time penalties when you're in production>.

=head1 REQUIRED MODULES

 Filter::Util::Call (any)
 IO::File (any)

=head1 IMPLEMENTATION

This version is completely written in Perl.  It uses a source filter to
provide its magic to the script being run B<and> an @INC handler for all
of the modules that are loaded otherwise.  Because the pod directives are
ignored by Perl during normal compilation, the source filter is B<not> needed
for production use so there will be B<no> performance penalty in that case.

=head1 CAVEATS

=head2 Overhead during development

Because the "ifdef" pragma uses a source filter for the invoked script, and
an @INC handler for all further required files, there is an inherent overhead
for compiling Perl source code.  Not loading ifdef.pm at all, causes the normal
pod section ignoring functionality of Perl to come in place (without any added
overhead).

=head2 No changing of environment variables during execution

Since the "ifdef" pragma performs all of this magic at compile time, it
generally does not make sense to change the values of applicable environment
variables at execution, as there will be no compiled code available to
activate.

=head2 Modules that use AutoLoader, SelfLoader, load, etc.

For the moment, these modules bypass the mechanism of this module.  An
interface with load.pm is on the TODO list.  Patches for other autoloading
modules are welcomed.

=head2 Doesn't seem to work on mod_perl

Unfortunately, there still seem to be problems with getting this moduled to
work reliably under mod_perl.

=head2 API FOR AUTOLOADING MODULES

The following subroutines are available for doing your own processing, e.g.
for inclusion in your own AUTOLOADing modules.  The subroutines are B<not>
exported: if you want to use them in your own namespace, you will need to
import them yourself thusly:

 *myprocess = \&ifdef::process;

would import the "ifdef::process" subroutine as "myprocess" in your namespace..

=head3 process

 ifdef::process( $direct );

 $processed = ifdef::process( $original );

The "process" subroutine allows you process a given string of source code
and have it processed in the same manner as which the source filter / @INC
handler of "ifdef.pm" would do.

There are two modes of calling: if called in a void context, it will process
the string and put the result in place.  An alternate method allows you to
keep a copy: if called in scalar or list context, the processed string will
be returned.

See L</"oneline"> of you want to process line by line.

=head3 reset

 &ifdef::reset;

The "reset" subroutine is needed only if you're doing your own processing with
the L</"oneline"> subroutine.  It resets the internal variables so that no
state of previous calls to L</"process"> (or the internally called source
filter or @INC handler) will remain.

=head3 oneline

 &ifdef::oneline;

The "oneline" subroutine does just that: it process a single line of source
code.  The line of source to be processed is expected to be in B<$_>.  The
processed line will be stored in B<$_> as well.  So there are no input or
output parameters.

See L</"process"> of you want to a string consisting of many lines in one go.

=head1 MODULE RATING

If you want to find out how this module is appreciated by other people, please
check out this module's rating at L<http://cpanratings.perl.org/i/ifdef> (if
there are any ratings for this module).  If you like this module, or otherwise
would like to have your opinion known, you can add your rating of this module
at L<http://cpanratings.perl.org/rate/?distribution=ifdef>.

=head1 CREDITS

Nick Kostirya for the idea of activating single line comments.

Konstantin Tokar for pointing out problems with empty code code blocks and
inline comments when the "all" flag was specified.  And providing patches!

=head1 AUTHOR

Elizabeth Mattijsen, <liz@dijkmat.nl>.

Please report bugs to <perlbugs@dijkmat.nl>.

=head1 COPYRIGHT

Copyright (c) 2004 Elizabeth Mattijsen <liz@dijkmat.nl>. All rights
reserved.  This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
