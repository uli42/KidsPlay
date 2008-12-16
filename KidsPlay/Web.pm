# KidsPlay (c) 2008 by Peter Watkins (peterw@tux.org)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2, which should be included with this software.

use strict;

package Plugins::KidsPlay::Web;

use Plugins::KidsPlay::Plugin;
use CGI;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Prefs;
use JSON::XS::VersionOneAndTwo;

my $kpPrefNamespace = 'plugin.KidsPlay';
my $kpPrefs = preferences($kpPrefNamespace);

sub needsClient {
	return 0;
}

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_KIDSPLAY_BASIC_SETTINGS');
}

sub page {
	# code in Plugin.pm protects us against CSRF attacks
        return 'plugins/KidsPlay/settings/basic.html';
}

sub handleWeb {
	my ($client, $params) = @_;
	# update macro
	$params->{'kidsplay'}->{'message'} = '';
	if ( defined($params->{KP_action}) ) {
		# loop through $params, look for "m-*-*"
		# check current pref value, set() if diff
		my $u = 0;
		foreach my $k (keys %$params) {
			if ( $k =~ m/^m\-(Boom|JVC|KP)\-(.*)$/ ) {
				my ($type,$button) = ($1,$2);
				my $thisMacro = $kpPrefs->get("macro-${type}-$button");
				if ( $thisMacro ne $params->{$k} ) {
					$kpPrefs->set("macro-${type}-$button",$params->{$k});
					++$u;
				}
			}
		}
		if ( $u > 0 ) {
			$params->{'kidsplay'}->{'message'} = "<p>$u ".string('KIDSPLAY_MACROS_UPDATED').'</p>';
		}
	}

	# list of buttons
	$params->{'kidsplay'}->{'macrooptions'} = '';
	$params->{'kidsplay'}->{'macro'} = '';
	my $c = 0;
	foreach my $type ( 'Boom', 'JVC', 'KP' ) {
		my $hashPtr = Plugins::KidsPlay::Plugin::getButtonHash($type);
		foreach my $k (sort keys %$hashPtr) {
			$params->{'kidsplay'}->{'macrooptions'} .= "<option value=\"$c\">$type - ".CGI::escapeHTML($hashPtr->{$k})."</option>\n";
			$params->{'kidsplay'}->{'macro'} .= "<span id=\"KP_s-$c\" style=\"display: none;\">$type - ".CGI::escapeHTML($hashPtr->{$k})."\n";
			$params->{'kidsplay'}->{'macro'} .= "<br /><textarea cols=\"60\" rows=\"5\" id=\"m-$type-$k\" name=\"m-$type-$k\">";
			my $thisMacro = $kpPrefs->get("macro-${type}-$k");
			$params->{'kidsplay'}->{'macro'} .= CGI::escapeHTML($thisMacro);
			$params->{'kidsplay'}->{'macro'} .= "</textarea>\n";
			$params->{'kidsplay'}->{'macro'} .= "<br /></span>\n";
			++$c;
		}
	}

        # make a "Home" link
	@{$params->{'pwd_list'}} = ( );

	return Slim::Web::HTTP::filltemplatefile('plugins/KidsPlay/settings/global.html', $params);
	#my $rc = $class->SUPER::handler($client, $params);
	#return $rc;
}

1;


