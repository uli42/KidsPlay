package Plugins::KidsPlay::PlayerSettings;

# KidsPlay Copyright (c) 2006-2008 Peter Watkins
#
# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::DateTime;
use Plugins::KidsPlay::Plugin;

my $prefs = preferences('plugin.KidsPlay');
my @prefNames = ('behaviorBoom','behaviorJVC','minVolume','maxVolume');

sub needsClient {
	return 1;
}

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_KIDSPLAY_PLAYER_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/KidsPlay/settings/player.html');
}

sub prefs {
	my ($class,$client) = @_;
	return ($prefs->client($client), @prefNames );
}

sub handler {
	my ($class, $client, $params) = @_;
	Plugins::KidsPlay::Plugin::initClientPrefs($client);
	# for bug 6873/change 19155
	if ($::VERSION ge '7.1') {
 		$params->{'pw'}->{'pref_prefix'} = 'pref_';
 	} else {
 		$params->{'pw'}->{'pref_prefix'} = '';
 	}
	### BUG -- validate prefs
	return $class->SUPER::handler($client, $params);
}

sub getPrefs {
	return $prefs;
}

1;

__END__
