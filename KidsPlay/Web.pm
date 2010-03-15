# KidsPlay (c) 2008-2009 by Peter Watkins (peterw@tux.org)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2, which should be included with this software.

use strict;

package Plugins::KidsPlay::Web;

use Plugins::KidsPlay::Plugin;
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
	$params->{'kidsplay'}->{'header'} = "<h2>".string('KIDSPLAY_MACROS_GLOBAL').'</h2>';
	$params->{'kidsplay'}->{'headerinfo'} = "<p>".string('KIDSPLAY_MACROS_GLOBAL_INFO').'</p>';
	my $whichScope = $kpPrefs;
	my $client = undef;
	if ( defined($params->{KP_scope}) && ($params->{KP_scope} =~ m/\S/) ) {
		# set client
		$client = Slim::Player::Client::getClient($params->{KP_scope});
		# set $whichScope
		$whichScope = $kpPrefs->client($client);
		$params->{'kidsplay'}->{'header'} = "<h2>".string('KIDSPLAY_MACROS_PER_PLAYER').$client->name().'</h2>';
		$params->{'kidsplay'}->{'headerinfo'} = "<p>".string('KIDSPLAY_MACROS_PER_PLAYER_INFO').'</p>';
	} else {
		$params->{'KP_scope'} = '';
	}
	if ( defined($params->{KP_action}) ) {
		# loop through $params, look for "m-*-*"
		# check current pref value, set() if diff
		my $u = 0;
		foreach my $k (keys %$params) {
			if ( $k =~ m/^m\-(Boom|Radio|Receiver|JVC|KP)\-(.*)$/ ) {
				my ($type,$button) = ($1,$2);
				my $thisMacro = $whichScope->get("macro-${type}-$button");
				if ( $thisMacro ne $params->{$k} ) {
					$whichScope->set("macro-${type}-$button",$params->{$k});
					Slim::Control::Request::notifyFromArray($client, ['kidsplaymacroset', $type, $button, $params->{$k}]);
					++$u;
				}
			} elsif ( $k =~ m/^l\-(Boom|Radio|Receiver|JVC|KP)\-(.*)$/ ) {
				my ($type,$button) = ($1,$2);
				$whichScope->set("macro-label-${type}-$button",$params->{$k});
			} 
		}
		if ( $u > 0 ) {
			$params->{'kidsplay'}->{'message'} = "<p>$u ".string('KIDSPLAY_MACROS_UPDATED').'</p>';
		}
	}

	$params->{'kidsplay'}->{'execStatus'} = string('DISABLED')." You must create a file named \"".Plugins::KidsPlay::Plugin::secretFileName()."\" on your server in order to use kidsplayexec.";
	if ( Plugins::KidsPlay::Plugin::secretFileExists() ) {
		$params->{'kidsplay'}->{'execStatus'} = string('ENABLED')." Your SECRET value is ".$kpPrefs->get('execSecret');
	}

	# list of buttons
	$params->{'kidsplay'}->{'macrooptions'} = '';
	$params->{'kidsplay'}->{'macro'} = '';
	my $c = 0;
	my @players = Slim::Player::Client::clients();
	foreach my $type ( 'Boom', 'Receiver', 'Radio', 'JVC', 'KP' ) {
		my $hashPtr = Plugins::KidsPlay::Plugin::getButtonHash($type);
		foreach my $k (sort keys %$hashPtr) {
			my $thisLabel = $whichScope->get("macro-label-${type}-$k");
			my $thisMacro = $whichScope->get("macro-${type}-$k");
			my $setIndicator = '';
			if ( $thisMacro  =~ m/\S/ ) { $setIndicator = ' * '; }
			my $labelString = '';
			if ( $thisLabel =~ m/\S/ ) { 
				$labelString = " - ".$thisLabel; 
				$setIndicator = '';
			}
			# use tooltip to make other macros or global macro visible
			my $others = '';
			my $otherIndicator = '';
			my $otherString = '';
			if ( $params->{'KP_scope'} eq '' ) {
				# do any players override this? (loop through @players)
				foreach my $p ( @players ) {
					my $m = Plugins::KidsPlay::Plugin::cleanMacro($kpPrefs->client($p)->get("macro-${type}-$k",$params->{$k}));
					if ( $m ne '' ) {
						$others .= "<a title=\"".&escape_html($m)."\">".$p->name()."</a>, ";
					}
				}
				if ( $others ne '' ) {
					$others =~ s/, $//;
					$otherString = "<br />".string('KIDSPLAY_MACROS_EXIST_FOR').$others."\n";
					$otherIndicator = '+';
				}
			} else {
				# is there a global macro for this?
				my $m = Plugins::KidsPlay::Plugin::cleanMacro($kpPrefs->get("macro-${type}-$k",$params->{$k}));
				if ( $m ne '' ) {
					$others .= "<a title=\"".&escape_html($m)."\">".string('KIDSPLAY_ALL_PLAYERS')."</a>, ";
					$otherString = "<br />".string('KIDSPLAY_MACROS_EXIST_FOR').$others."\n";
					$otherIndicator = '+';
				}
			}
			$params->{'kidsplay'}->{'macrooptions'} .= "<option value=\"$c\">$type - ".&escape_html($hashPtr->{$k}).$otherIndicator.$setIndicator.&escape_html($labelString)."</option>\n";
			#$params->{'kidsplay'}->{'macro'} .= "<span id=\"KP_s-$c\" style=\"display: none;\">$type - ".&escape_html($hashPtr->{$k})."\n";
			$params->{'kidsplay'}->{'macro'} .= "<span id=\"KP_s-$c\" style=\"display: none;\">";
			$params->{'kidsplay'}->{'macro'} .= $otherString;
			$params->{'kidsplay'}->{'macro'} .= "<br />".&escape_html(string('DESCRIPTION')).": <input size=\"15\" id=\"l-$type-$k\" name=\"l-$type-$k\" value=\"".&escape_html($thisLabel)."\">";
			$params->{'kidsplay'}->{'macro'} .= "<br /><textarea cols=\"60\" rows=\"5\" id=\"m-$type-$k\" name=\"m-$type-$k\">";
			my $thisMacro = $whichScope->get("macro-${type}-$k");
			$params->{'kidsplay'}->{'macro'} .= &escape_html($thisMacro);
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

# improved from Slim/Utils/MemoryUsage
sub escape_html($) {
	my $str = shift;
	$str =~ s/&/&amp;/g;
	$str =~ s/</&lt;/g;
	$str =~ s/>/&gt;/g;
	$str =~ s/\"/&quot;/g;
	$str =~ s/\'/&apos;/g;
	return $str;
}

1;


