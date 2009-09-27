# KidsPlay (c) 2008 by Peter Watkins (peterw@tux.org)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2, which should be included with this software.

use strict;

package Plugins::KidsPlay::GlobalSettings;

use Plugins::KidsPlay::Plugin;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Prefs;
use JSON::XS::VersionOneAndTwo;

use base qw(Slim::Web::Settings);

my $kpPrefNamespace = 'plugin.KidsPlay';
my $kpPrefs = preferences($kpPrefNamespace);

sub needsClient {
	return 0;
}

sub name {
	if ( substr($::VERSION,0,3) lt 7.4 ) {
		return Slim::Web::HTTP::protectName('PLUGIN_KIDSPLAY_BASIC_SETTINGS');
	}
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_KIDSPLAY_BASIC_SETTINGS');
}

sub page {
	# code in Plugin.pm protects us against CSRF attacks
        return 'plugins/KidsPlay/settings/basic.html';
}

	
sub handler {
	my ($class, $client, $params) = @_;
	my $rc = $class->SUPER::handler($client, $params);
	return $rc;
}

1;


