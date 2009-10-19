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

# only for clients that send IR to the server (will open up once there's
# a SqueezePlay Lua applet to run on SP players)
sub validFor {
	my $class = shift;
	my $client = shift;
	return ( (! $client->isa("Slim::Player::SqueezePlay")) || ($client->model() eq 'baby') );
}

sub name {
        if ( substr($::VERSION,0,3) lt 7.4 ) {
                return Slim::Web::HTTP::protectName('PLUGIN_KIDSPLAY_PLAYER_SETTINGS');
        }
        return Slim::Web::HTTP::CSRF->protectName('PLUGIN_KIDSPLAY_PLAYER_SETTINGS');
}

sub page {
        if ( substr($::VERSION,0,3) lt 7.4 ) {
		return Slim::Web::HTTP::protectURI('plugins/KidsPlay/settings/player.html');
        }
        return Slim::Web::HTTP::CSRF->protectURI('plugins/KidsPlay/settings/player.html');
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
 	$params->{'pw'}->{'jvc_style'} = '';
 	$params->{'pw'}->{'boom_style'} = '';
	if ( ($client->model() ne 'baby') && (! $client->isa( "Slim::Player::Boom")) && (! $client->isa( "Slim::Player::Receiver")) ) {
 		$params->{'pw'}->{'boom_style'} = 'display: none;';
	}
	if ( $client->model() eq 'baby' ) {
 		$params->{'pw'}->{'jvc_style'} = 'display: none;';
 		$params->{'pw'}->{'rnote'} = $client->string('PLUGIN_KIDSPLAY_RADIO_NOTE');
	}
	### BUG -- validate prefs
	return $class->SUPER::handler($client, $params);
}

sub getPrefs {
	return $prefs;
}

1;

__END__
