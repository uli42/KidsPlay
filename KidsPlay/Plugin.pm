# KidsPlay copyright (c) 2008-2009 by Peter Watkins (peterw@tux.org) 
# All Rights Reserved
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

package Plugins::KidsPlay::Plugin;

use Slim::Control::Request;
use Slim::Hardware::IR;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Prefs;
use Plugins::KidsPlay::PlayerSettings;
use Plugins::KidsPlay::GlobalSettings;
use Plugins::KidsPlay::Web;

# ---------------------- settings ----------------------------
my $minWait = 2.5;	# don't act if 'ir' command fired less than $minWait seconds after last command
# ---------------------- settings ----------------------------

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.KidsPlay',
	'defaultLevel' => 'WARN',
#	'defaultLevel' => 'DEBUG',
	'description'  => &getDisplayName(),
});

my $prefs = preferences('plugin.KidsPlay');
my $serverPrefs = preferences('server');

use vars qw($VERSION);
$VERSION = &rcsVersion();

# whether we need to add our callback function to the stack
my $callbackSet = 0;

# whether we're enabled (the callback remains in the function 
# stack after "disabling" the plugin, so we need to keep track of this)
my $pluginEnabled = 0;

# need to keep track of original function
my $originalIRCommand;
my @commandQueue;

# per-client
my %lastIRCode;
my %lastIRTime;

my %supportedButtons = (
	'KP' => {
		"pre" => string('KIDSPLAY_PRE_MACRO'),
		"post" => string('KIDSPLAY_POST_MACRO'),
	},
	'JVC' => {
		"0" => string('KIDSPLAY_BUTTON')." 0",
		"1" => string('KIDSPLAY_BUTTON')." 1",
		"2" => string('KIDSPLAY_BUTTON')." 2",
		"3" => string('KIDSPLAY_BUTTON')." 3",
		"4" => string('KIDSPLAY_BUTTON')." 4",
		"5" => string('KIDSPLAY_BUTTON')." 5",
		"6" => string('KIDSPLAY_BUTTON')." 6",
		"7" => string('KIDSPLAY_BUTTON')." 7",
		"8" => string('KIDSPLAY_BUTTON')." 8",
		"9" => string('KIDSPLAY_BUTTON')." 9",
		"add" => string("ADD").' '.string('KIDSPLAY_BUTTON'),
		"arrow_down" => string("DOWN").' '.string('KIDSPLAY_BUTTON'),
		"arrow_left" => string("KIDSPLAY_LEFT").' '.string('KIDSPLAY_BUTTON'),
		"arrow_right" => string("KIDSPLAY_RIGHT").' '.string('KIDSPLAY_BUTTON'),
		"arrow_up" => string("UP").' '.string('KIDSPLAY_BUTTON'),
		"brightness_down" => string("SETUP_GROUP_BRIGHTNESS").' '.string("DOWN").' '.string('KIDSPLAY_BUTTON'),
		"brightness_up" => string("SETUP_GROUP_BRIGHTNESS").' '.string("UP").' '.string('KIDSPLAY_BUTTON'),
		#"format" => string("FORMAT").' '.string('KIDSPLAY_BUTTON'),
		"fwd" => string("FFWD").' '.string('KIDSPLAY_BUTTON'),
		"menu_home" => string("HOME").' '.string('KIDSPLAY_BUTTON'),
		"muting" => string("MUTE").' '.string('KIDSPLAY_BUTTON'),
		"now_playing" => string("NOW_PLAYING").' '.string('KIDSPLAY_BUTTON'),
		"pause" => string("PAUSE").' '.string('KIDSPLAY_BUTTON'),
		"play" => string("PLAY").' '.string('KIDSPLAY_BUTTON'),
		"power" => string("POWER").' '.string('KIDSPLAY_BUTTON'),
		"repeat" => string("REPEAT").' '.string('KIDSPLAY_BUTTON'),
		"rew" => string("REW").' '.string('KIDSPLAY_BUTTON'),
		"shuffle" => string("SHUFFLE").' '.string('KIDSPLAY_BUTTON'),
		"size" => string("KIDSPLAY_SIZE").' '.string('KIDSPLAY_BUTTON'),
		"sleep" => string("SLEEP").' '.string('KIDSPLAY_BUTTON'),
		"stop" => string("STOP").' '.string('KIDSPLAY_BUTTON'),
		"voldown" => string("VOLUME").' '.string('DOWN').' '.string('KIDSPLAY_BUTTON'),
		"volup" => string("VOLUME").' '.string('UP').' '.string('KIDSPLAY_BUTTON'),
	},
	'Boom' => {
		'preset_1' => string('KIDSPLAY_PRESET_BUTTON').' 1',
		'preset_2' => string('KIDSPLAY_PRESET_BUTTON').' 2',
		'preset_3' => string('KIDSPLAY_PRESET_BUTTON').' 3',
		'preset_4' => string('KIDSPLAY_PRESET_BUTTON').' 4',
		'preset_5' => string('KIDSPLAY_PRESET_BUTTON').' 5',
		'preset_6' => string('KIDSPLAY_PRESET_BUTTON').' 6',
	},
);
	
# initialize
sub initPlugin {
	if ( $callbackSet == 0 ) {
		# wait a few seconds to register hooks to better ensure that we wrap
		# the IR and button commands last
		Slim::Utils::Timers::setTimer('moot', (Time::HiRes::time() + 3), \&registerHooks);
		# player settings
		Plugins::KidsPlay::PlayerSettings->new();
		# global settings (just a redir)
		Plugins::KidsPlay::GlobalSettings->new();
		# the real global settings page
		Slim::Web::HTTP::addPageFunction("plugins/KidsPlay/settings/global.html", \&Plugins::KidsPlay::Web::handleWeb);
		Slim::Web::HTTP::protect('plugins\/KidsPlay\/settings\/global\.html\?.*\bKP_action\=');
		# init prefs
		&initPrefs();
		# register a CLI command
		Slim::Control::Request::addDispatch(['kidsplayvolume','_delta'], [1, 0, 0, \&volumeCLI]);
		Slim::Web::HTTP::protectCommand('kidsplayvolume');
		Slim::Control::Request::addDispatch(['kidsplaytoggleclientpref','_prefname','_val1','_val2'], [1, 0, 0, \&toggleclientprefCLI]);
		Slim::Web::HTTP::protectCommand('kidsplaytoggleclientpref');
	}
	# note that we should act
	$pluginEnabled = 1;
	if ( defined($ENV{'PRETEND_IR_TYPE'}) && ($ENV{'PRETEND_IR_TYPE'} ne '') ) { 
		my $type = $ENV{'PRETEND_IR_TYPE'}; 
		$log->warn("pretending that all IR codes are $type codes");
	}
}

sub toggleclientprefCLI {
        my $request = shift;
	# check this is the correct command.
	if ($request->isNotCommand([['kidsplaytoggleclientpref']])) {
		$request->setStatusBadDispatch();
		return;
	}
	# get the parameters
	my $client = $request->client();
	my $name = $request->getParam('_prefname');
	my $val1 = $request->getParam('_val1');
	my $val2 = $request->getParam('_val2');
	my $ns = 'server';
	if ( $name =~ m/^(.*)\.([^\.]{1,})$/ ) {
		$ns = $1; $name = $2;
	}
	my $p = preferences($ns);
	if (! defined($p->client($client)->get($name)) ) {
		$p->client($client)->set($name,$val1);
	} elsif ( $p->client($client)->get($name) eq $val2 ) {
		$p->client($client)->set($name,$val1);
	} else {
		$p->client($client)->set($name,$val2);
	}
	$request->setStatusDone();
}

sub volumeCLI {
        my $request = shift;
	# check this is the correct command.
	if ($request->isNotCommand([['kidsplayvolume']])) {
		$request->setStatusBadDispatch();
		return;
	}
	# get the parameters
	my $client = $request->client();
	my $delta = $request->getParam('_delta');
	# initialize client prefs
	&initClientPrefs($client);
	# normalize delta
	$delta =~ s/[^0-9\+\-]//g;
	# new volume
	my $newVol = $serverPrefs->client($client)->get('volume');
	if ( $delta =~ m/^[\+\-]/ ) {
		$newVol += $delta;
	} else {
		$newVol = $delta;
	}
	if ( $newVol < $prefs->client($client)->get('minVolume') ) {
		$newVol = $prefs->client($client)->get('minVolume');
	}
	if ( $newVol > $prefs->client($client)->get('maxVolume') ) {
		$newVol = $prefs->client($client)->get('maxVolume');
	}
	Slim::Control::Request::executeRequest($client, ['mixer','volume',$newVol], undef, undef);
	$request->setStatusDone();
}

sub initClientPrefs {
	my $client= shift;
	if ( (!defined($prefs->client($client)->get('minVolume'))) || ($prefs->client($client)->get('minVolume') eq '') ) {
		$prefs->client($client)->set('minVolume',0);
	}
	if ( (!defined($prefs->client($client)->get('maxVolume'))) || ($prefs->client($client)->get('maxVolume') eq '') ) {
		$prefs->client($client)->set('maxVolume',100);
	}
	my $boom = $prefs->client($client)->get('behaviorBoom');
	my $jvc = $prefs->client($client)->get('behaviorJVC');
	if ( (!defined($boom)) ||
		($boom eq '') ) {
		$prefs->client($client)->set('behaviorBoom','PLUGIN_KIDSPLAY_CHOICE_NORMAL');
	}
	if ( (!defined($jvc)) ||
		($jvc eq '') ) {
		$prefs->client($client)->set('behaviorJVC','PLUGIN_KIDSPLAY_CHOICE_NORMAL');
	}
}

sub registerHooks {
	if ( $callbackSet == 0 ) {
		$log->info("wrapping button functions\n");
		$originalIRCommand = Slim::Control::Request::addDispatch(['ir','_ircode','_time'],[1, 0, 0, \&KidsPlay_irCommand]);
		if ( (!defined($originalIRCommand)) || (ref($originalIRCommand ) ne 'CODE') ) {
			$log->warn("problem wrapping button command!\n");
		}
		$callbackSet = 1; 
	}
}

sub shutdownPlugin {
	# we should not act
	$pluginEnabled = 0;
}

sub enabled {
	if ( substr($::VERSION,0,3) gt '7.2' ) {
		$log->warn("This plugin has not been tested with SlimServer newer than 7.2.x\n");
	}
	if ( substr($::VERSION,0,3) lt '7.2' ) {
		$log->warn("This plugin has not been tested with SlimServer older than 7.2.x\n");
	}
	# this uses the Slim::Control::Request API that's in 6.5.x
	return ($::VERSION ge '7.0');
}

sub rcsVersion() {
	my $RcsVersion = '$Revision: 1.21 $';
	$RcsVersion =~ s/.*:\s*([0-9\.]*).*$/$1/;
	return $RcsVersion;
}

sub getDisplayName() {
	return 'PLUGIN_KIDSPLAY';
}

# our wrapper function
sub KidsPlay_irCommand {
	my @args = @_;
	my $request = $args[0];
	my $ircode = $request->getParam('_ircode');
	my $client = $request->client();
	if (! defined($client) ) {
		$log->info("no client! calling original IR command");
		return &$originalIRCommand(@args);
	}
	my $id = $client->id();
	my $codename = Slim::Hardware::IR::lookupCodeBytes($client,$ircode);
	# remove down (Boom macros are unqualified & we only act on down)
	$codename =~ s/\.down$//;
	my $type = undef;
	# following IFF jvc code:
	# Boom presets: 00010020-00010025 down, 00020020-00020025 up
	if ( $ircode =~ m/^0000/) {
		$type = 'JVC';
	} elsif ( $ircode =~ m/^000[12]002[0-5]/) {
		$type = 'Boom';
	}
	# dev hack
	if ( defined($ENV{'PRETEND_IR_TYPE'}) && ($ENV{'PRETEND_IR_TYPE'} ne '') ) { 
		$type = $ENV{'PRETEND_IR_TYPE'}; 
	}
	if (! defined($type) ) {
		# not JVC or not a Boom preset
		return &$originalIRCommand(@args);
	}
	my $pref = &behaviorPref($client,$type);
	if ( $pref eq 'PLUGIN_KIDSPLAY_CHOICE_NORMAL' ) {
		return &$originalIRCommand(@args);
	}
	my $now = Time::HiRes::time();
	my $then = $lastIRTime{$id};
	my $what = $lastIRCode{$id};
	my $wait = $prefs->get("wait${type}");
	if ( (!defined($then)) || (defined($what) && ($what ne $codename)) || (($now - $then) > $wait) ) {
		$log->info("client $id sent $type IR code for \"$codename\" (IR code $ircode)");
	}
	my $done = 0;
	my $macro = &getMacro($codename,$type);
	if ( $macro =~ m/\S/ ) {
		$log->debug("we have a macro for $type - $codename ; last execute $then last code $what now $now");
		$done = 1;
		if ( (!defined($then)) || (defined($what) && ($what ne $codename)) || (($now - $then) > $wait) ) {
			# pre-macro?
			my $macro2 = &getMacro('pre','KP');
			$macro2 =~ s/\;\s*$//s;
			if ( $macro2 =~ m/\S/ ) {
				&executeKidsPlay($client,'KP','pre',$macro2);
			}
			&executeKidsPlay($client,$type,$codename,$macro);
			# post-macro?
			$macro2 = &getMacro('post','KP');
			$macro2 =~ s/\;\s*$//s;
			if ( $macro2 =~ m/\S/ ) {
				&executeKidsPlay($client,'KP','post',$macro2);
			}
		}
	}
	$lastIRCode{$id} = $codename;
	$lastIRTime{$id} = Time::HiRes::time();
	if ( ($done == 1) || ($pref eq 'PLUGIN_KIDSPLAY_CHOICE_ONLY') ) { 
		# had a macro to execute, or no fallthrough
		return; 
	}
	return &$originalIRCommand(@args);
}

sub getMacro($$) {
	my ($shortcode,$type) = @_;
	# use global prefs for "macro-$type-$shortcode"
	my $macro = $prefs->get("macro-$type-$shortcode");
	$macro =~ s/^\s*//s;
	$macro =~ s/\;?\s*$//s;
	return $macro;
}

sub initPrefs(){
	my $waitJVC = $prefs->get("waitJVC");
	if ( (!defined($waitJVC)) || ($waitJVC eq '') ) {
		$prefs->set("waitJVC",$minWait);
		$prefs->set("waitBoom",0);
	}
}

sub executeKidsPlay($$$) {
	my ($client,$type,$buttoncode,$macro) = @_;
	$log->debug("asked to execute KidsPlay macro $type - $buttoncode");
	my $shortcode = $buttoncode;
	$shortcode =~ s/\..*$//;
	my $rc = 0;
	if ( defined($macro) ) {
		my $id = $client->id();
		$macro =~ s/[\;\s]*$//s;	# strip terminal chars
		my @ms = split(/\;/,$macro);
		foreach my $m (@ms) {
			$m =~ s/^\s*//;
			$m =~ s/\s*$//;
			my @fields = &parseFields($m);
			push @fields, $client;
			&addToQueue(@fields);
			$rc = 1;
		}
	}
	return $rc;
}

sub addToQueue {
	# get command args
	my @cmdArgs = @_;
	# add to queue
	push @commandQueue, \@cmdArgs;
	# if nothing was in queue, tell scheduler we need to process the queue
	if ( scalar(@commandQueue) == 1) {
		Slim::Utils::Scheduler::add_task(\&processCommandFromQueue);
	}
}

# sub to run from Slim::Utils::Scheduler to reduce blocking
sub processCommandFromQueue() {
	if ( scalar(@commandQueue) > 0 ) {
		my $cmdPtr = shift @commandQueue;
		my @cmdArgs = @{$cmdPtr};
		my $client = pop @cmdArgs;
		my $id = $client->id();
		$log->info("for client $id, execute \"".join('" "',@cmdArgs)."\"");
		Slim::Control::Request::executeRequest($client, \@cmdArgs, undef, undef);
	}
	# return 1 if there are more items to process
	if ( scalar(@commandQueue) > 0 ) {
		return 1;
	}
	# indicate that we're done with the queue
	return 0;
}

sub behaviorPref($$) {
	my $client = shift;
	my $type = shift;
	&initClientPrefs($client);
	return $prefs->client($client)->get("behavior${type}");
}	

# sub to handle quoted fields, e.g. 'playlist play "/path/with some spaces/playlist.m3u"'
sub parseFields($) {
        my $in = shift;
	my @qs = split(/\"/,$in);
	my @cooked = ();
	for (my $q = 0; $q < scalar(@qs); ++$q) {
		if ( ($q % 2) == 0 ) {
			# not quoted
			$qs[$q] =~ s/^\s*//;
			$qs[$q] =~ s/\s*$//;
			push @cooked, split(/\s/,$qs[$q]);
		} else {
			# quoted
			push @cooked, $qs[$q];
		}
	}
	return @cooked;
}

sub getButtonHash($) {
	my $type = shift;
	my $hashPtr = $supportedButtons{$type};
	return $hashPtr;
}

1;

