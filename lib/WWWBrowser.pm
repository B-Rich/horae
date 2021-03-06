#!/usr/bin/env perl
# -*- perl -*-

#
# $Id: WWWBrowser.pm,v 2.23 2003/02/05 16:39:10 eserte Exp $
# Author: Slaven Rezic
#
# Modified somewhat by Bruce Ravel
#
# Copyright (C) 1999,2000,2001,2003 Slaven Rezic. All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

package WWWBrowser;

use strict;
use vars qw(@unix_browsers $VERSION $initialized $os $fork
	    $got_from_config $ignore_config);

$VERSION = sprintf("%d.%02d", q$Revision: 2.23 $ =~ /(\d+)\.(\d+)/);

@unix_browsers = qw(_default_gnome _default_kde
		    opera iceweasel galeon epiphany firefox konqueror mozilla netscape Netscape kfmclient
		    w3m lynx
		    dillo mosaic Mosaic chimera arena tkweb
		    explorer) if !@unix_browsers;

init();

sub init {
    if (!$initialized) {
	if (!defined $main::os) {
	    $os = ($^O eq 'MSWin32' ? 'win' : 'unix');
	} else {
	    $os = $main::os;
	}
	if (!defined &main::status_message) {
	    eval 'sub status_message { warn $_[0] }';
	} else {
	    eval 'sub status_message { main::status_message(@_) }';
	}
	$fork = 1;
	$initialized++;
	get_from_config();
    }
}

sub start_browser {
    my $url = shift;
    my(%args) = @_;

    if ($os eq 'win') {
	if (!eval 'require Win32Util;
	           Win32Util::start_html_viewer($url)') {
	    # if this fails, just try to start explorer
	    system("start explorer $url");
	    # otherwise croak
	    if ($?/256 != 0) {
		status_message("Can't find HTML viewer.", "err");
		return 0;
	    }
	}
	return 1;
    }

    my @browsers = @unix_browsers;
    if ($args{-browser}) {
	unshift @browsers, delete $args{-browser};
    }

    foreach my $browser (@browsers) {
	next if (!is_in_path($browser));
	if ($browser =~ /^(lynx|w3m)$/) { # text-orientierte Browser
	    if (defined $ENV{DISPLAY} && $ENV{DISPLAY} ne "") {
		foreach my $term (qw(xterm kvt gnome-terminal)) {
		    if (is_in_path($term)) {
			exec_bg($term,
				($term eq 'gnome_terminal' ? '-x' : '-e'),
				$browser, $url);
			return 1;
		    }
		}
	    } else {
		# without X11: not in background!
		system($browser, $url);
		return 1;
	    }
	    next;
	}

	if ((!defined $ENV{DISPLAY} || $ENV{DISPLAY} eq '') &&
	    $^O ne 'cygwin') {
	    next;
	}
	# After this point only X11 browsers or cygwin as a special case

	my $url = $url;
	if ($browser eq '_default_gnome') {
	    eval {
		my $cmdline = _get_cmdline_for_url_from_Gnome($url);
		exec_bg($cmdline);
		return 1;
	    };
	} elsif ($browser eq '_default_kde') {
	    # NYI
	} elsif ($browser eq 'konqueror') {
	    return 1 if open_in_konqueror($url, %args);
	} elsif ($browser eq 'galeon') {
	    return 1 if open_in_galeon($url, %args);
	} elsif ($browser eq 'mozilla') {
	    return 1 if open_in_mozilla($url, %args);
	} elsif ($browser =~ /^mosaic$/i &&
	    $url =~ /^file:/ && $url !~ m|file://|) {
	    $url =~ s|file:/|file://localhost/|;
	} elsif ($browser eq 'kfmclient') {
	    # kfmclient loads kfm, which loads and displays all KDE icons
	    # on the desktop, even if KDE is not running at all.
	    exec_bg("kfmclient", "openURL", $url);
	    return 1 if (!$?)
	} elsif ($browser eq 'netscape') {
	    if ($os eq 'unix') {
		my $lockfile = "$ENV{HOME}/.netscape/lock";
		if (-l $lockfile) {
		    my($host,$pid) = readlink($lockfile) =~ /^(.*):(\d+)$/;
		    # XXX check $host
		    # Check whether Netscape stills lives:
		    if (defined $pid && kill 0 => $pid) {
			if ($args{-oldwindow}) {
			    exec_bg("netscape", "-remote", "openURL($url)");
			} else {
			    exec_bg("netscape", "-remote", "openURL($url,new)");
			}
		        # XXX further options: mailto(to-adresses)
			# XXX check return code?
			return 1;
		    }
		}
		exec_bg("netscape", $url);
		return 1;
	    }
	} else {
	    exec_bg($browser, $url);
	    return 1;
	}
    }

    status_message("Can't find HTML viewer.", "err");

    return 0;
}

sub open_in_konqueror {
    my $url = shift;
    my(%args) = @_;
    if (is_in_path("dcop") && is_in_path("konqueror")) {

	# first try old window (if requested)
	if ($args{-oldwindow}) {
	    my $konq_name;
	    foreach my $l (split /\n/, `dcop konqueror KonquerorIface getWindows`) {
		if ($l =~ /(konqueror-mainwindow\#\d+)/) {
		    $konq_name = $1;
		    last;
		}
	    }

	    if (defined $konq_name) {
		system(qw/dcop konqueror/, $konq_name, qw/openURL/, $url);
		return 1 if ($?/256 == 0);
	    }
	}

	# then try to send to running konqueror process:
	system(qw/dcop konqueror KonquerorIface openBrowserWindow/, $url);
	return 1 if ($?/256 == 0);

	# otherwise start a new konqueror
	exec_bg("konqueror", $url);
	return 1; # if ($?/256 == 0);
    }
    0;
}

sub open_in_galeon {
    my $url = shift;
    my(%args) = @_;
    if (is_in_path("galeon")) {

	$url = _guess_and_expand_url($url) if $args{-expandurl};

	# first try old window (if requested)
	if ($args{-oldwindow}) {
	    system("galeon", "-x", $url);
	    return 1 if ($?/256 == 0);
	}

	exec_bg("galeon", "-n", $url);
	return 1 if ($?/256 == 0);
	return 0;
    }
    0;
}

sub open_in_mozilla {
    my $url = shift;
    my(%args) = @_;
    if (is_in_path("mozilla")) {
	if ($args{-oldwindow}) {
	    system("mozilla", "-remote", "openURL($url)");
	} else {
	    system("mozilla", "-remote", "openURL($url,new-tab)");
	}
	return 1 if ($?/256 == 0);

	# otherwise start a new mozilla process
	exec_bg("mozilla", $url);
	return 1; # if ($?/256 == 0);
    }
    0;
}

sub exec_bg {
    my(@cmd) = @_;
    if ($os eq 'unix') {
	eval {
	    if (!$fork || fork == 0) {
		exec @cmd;
		die "Can't exec @cmd: $!";
	    }
	};
    } else {
	# XXX use Spawn
	system(join(" ", @cmd) . ($fork ? "&" : ""));
    }
}

sub _get_cmdline_for_url_from_Gnome {
    my($url) = @_;
    (my $url_scheme = $url) =~ s/^([^:]+).*/$1/; # use URI.pm?
    my $curr_section;
    my $default_cmdline;
    my $cmdline;
    if (open(GNOME, "$ENV{HOME}/.gnome/Gnome")) {
	while(<GNOME>) {
	    chomp;
	    if (/^\[(.*)\]/) {
		$curr_section = $1;
	    } elsif (defined $curr_section && $curr_section eq 'URL Handlers' && /^(default|\Q$url_scheme\E)-show=(.*)/) {
		if ($1 eq 'default') {
		    $default_cmdline = $2;
		} else {
		    $cmdline = $2;
		}
	    }
	}
	close GNOME;
    }
    if (!defined $cmdline) {
	$cmdline = $default_cmdline;
    }
    if (!defined $cmdline) {
	die "Can't find command for scheme $url_scheme";
    }
    $cmdline =~ s/%s/$url/g;
    $cmdline;
}

# XXX document get_from_config, $ignore_config, ~/.wwwbrowser
sub get_from_config {
    if (!$got_from_config && !$ignore_config && $ENV{HOME} && open(CFG, "$ENV{HOME}/.wwwbrowser")) {
	my @browser;
	while(<CFG>) {
	    chomp;
	    push @browser, $_;
	}
	close CFG;
	$got_from_config++;
	unshift @unix_browsers, @browser;
    }
}

sub _guess_and_expand_url {
    my $url = shift;
    if ($url =~ m|^[a-z]+://|) {
	$url;
    } elsif ($url =~ m|^www|) {
	"http://$url";
    } elsif ($url =~ m|^ftp|) {
	"ftp://$url";
    } else {
	$url;
    }
}

# REPO BEGIN
# REPO NAME file_name_is_absolute /home/e/eserte/src/repository 
# REPO MD5 89d0fdf16d11771f0f6e82c7d0ebf3a8
BEGIN {
    if (eval { require File::Spec; defined &File::Spec::file_name_is_absolute }) {
	*file_name_is_absolute = \&File::Spec::file_name_is_absolute;
    } else {
	*file_name_is_absolute = sub {
	    my $file = shift;
	    my $r;
	    if ($^O eq 'MSWin32') {
		$r = ($file =~ m;^([a-z]:(/|\\)|\\\\|//);i);
	    } else {
		$r = ($file =~ m|^/|);
	    }
	    $r;
	};
    }
}
# REPO END

# REPO BEGIN
# REPO NAME is_in_path /home/e/eserte/src/repository 
# REPO MD5 81c0124cc2f424c6acc9713c27b9a484
sub is_in_path {
    my($prog) = @_;
    return $prog if (file_name_is_absolute($prog) and -f $prog and -x $prog);
    require Config;
    my $sep = $Config::Config{'path_sep'} || ':';
    foreach (split(/$sep/o, $ENV{PATH})) {
	if ($^O eq 'MSWin32') {
	    # maybe use $ENV{PATHEXT} like maybe_command in ExtUtils/MM_Win32.pm?
	    return "$_\\$prog"
		if (-x "$_\\$prog.bat" ||
		    -x "$_\\$prog.com" ||
		    -x "$_\\$prog.exe" ||
		    -x "$_\\$prog.cmd");
	} else {
	    return "$_/$prog" if (-x "$_/$prog" && !-d "$_/$prog");
	}
    }
    undef;
}
# REPO END

1;

__END__

=head1 NAME

WWWBrowser - platform independent mean to start a WWW browser

=head1 SYNOPSIS

    use WWWBrowser;
    WWWBrowser::start_browser($url, -oldwindow => 1);

=head1 DESCRIPTION

=head2 start_browser($url [, %args])

Start a web browser with the specified URL. The process is started in
background.

The following optional parameters are recognized:

=over 4

=item -oldwindow => $bool

Normally, the URL is loaded into a new window, if possible. With
C<-oldwindow> set to a false window, C<WWWBrowser> will try to re-use
a browser window.

=item -browser => $browser

Use (preferebly) the named browser C<$browser>. See L</CONFIGURATION>
for a some browser specialities. This option will only work for unix.

=back

=head1 CONFIGURATION

For unix, the global variable C<@WWWBrowser::unix_browsers> can be set
to a list of preferred web browsers. The following browsers are
handled specially:

=over 4

=item lynx, w3m

Text oriented browsers, which are opened in an C<xterm>, C<kvt> or
C<gnome-terminal> (if running under X11). If not running under X11,
then no background process is started.

=item kfmclient

Use C<openURL> method of kfm.

=item netscape

Use C<-remote> option to re-use a running netscape process, if
possible.

=item _default_gnome

Look into the C<~/.gnome/Gnome> configuration file for the right browser.

=item _default_kde

NYI.

=back

The following variables can be defined globally in the B<main>
package:

=over 4

=item C<$os>

Short name of operating system (C<win>, C<mac> or C<unix>).

=item C<&status_messages>

Error handling function (instead of default C<warn>).

=back

=head1 REQUIREMENTS

For Windows, the L<Win32Util|Win32Util> module should be installed in
the path.

=head1 AUTHOR

Slaven Rezic <slaven@rezic.de>

=head1 COPYRIGHT

Copyright (c) 1999,2000,2001,2003 Slaven Rezic. All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Win32Util|Win32Util>.
