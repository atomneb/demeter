package Ifeffit::Demeter::UI::Hephaestus::Common;

use warnings;
use strict;
use version;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = qv("1.0.0");

use Readonly;
Readonly my $PI    => 4 * atan2 1, 1;
Readonly my $HBARC => 1973.27053324;

use Wx qw(wxVERSION_STRING);

require Exporter;
@ISA       = qw(Exporter);
#@EXPORT    = qw(e2l);
@EXPORT_OK = qw(e2l hversion hcopyright hdescription slurp);

sub hversion {
  return $VERSION;
};

sub hcopyright {
  return "copyright (c) 2008 Bruce Ravel"
};

sub hdescription {
  my $wxversion = wxVERSION_STRING;
  my $string = "A souped-up periodic table for the X-ray absorption spectroscopist\n";
  $string   .= "Using perl $], $wxversion, wxPerl $Wx::VERSION  ";
};

sub e2l {
  ($_[0] and ($_[0] > 0)) or return "";
  return 2*$PI*$HBARC / $_[0];
};


sub slurp {
  my $file = shift;
  local $/;
  open(my $FH, $file);
  my $text = <$FH>;
  close $FH;
  return $text;
};


=head1 NAME

Ifeffit::Demeter::UI::Hephaestus::Common - Common functions used in Hephaestus

=head1 VERSION

This documentation refers to Ifeffit::Demeter version 0.2.

=head1 SYNOPSIS

This module contains functions used by many parts of Hephaestus.

  use Ifeffit::Demeter::UI::Hephaestus::Common qw(e2l);

=head1 DESCRIPTION

Several common functions are conatined in this moduel for use
throughout Hephaestus.

=over 4

=item C<e2l>

Convert between energy and wavelength.

  $l = e2l($e);
   #  or
  $e = e2l($l);

=item C<slurp>

Slurp an entire file into a scalar.

  $contents = slurp($filename);

=item C<hversion>

Return a string giving the Hephaestus version number.

=item C<hcopyright>

Return a string giving the Hephaestus copyright statement.

=item C<hdescription>

Return a string giving a description of Hephaestus' operating
environment, including version numbers for perl, WxWidgets, and
WxPerl.

=back

=head1 CONFIGURATION


=head1 DEPENDENCIES

Demeter's dependencies are in the F<Bundle/DemeterBundle.pm> file.

=head1 BUGS AND LIMITATIONS

Please report problems to Bruce Ravel (bravel AT bnl DOT gov)

Patches are welcome.

=head1 AUTHOR

Bruce Ravel (bravel AT bnl DOT gov)

L<http://cars9.uchicago.edu/~ravel/software/>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006-2008 Bruce Ravel (bravel AT bnl DOT gov). All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlgpl>.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut
