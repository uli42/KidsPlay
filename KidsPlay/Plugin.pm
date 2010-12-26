# KidsPlay copyright (c) 2008-2010 by Peter Watkins (peterw@tux.org) 
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

# ---------------------- settings ----------------------------
my $minWait = 2.5;	# don't act if 'ir' command fired less than $minWait seconds after last command
# protection for 'kidsplayexec' CLI command
my $execRequiresCRSFProtection = 1;		# at least "medium" level
my $execRequiresPasswordProtection = 1;
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
my $originalButtonCommand;
my $originalJiveFavoritesCommand;
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
	'Radio' => {
		'preset_1' => string('KIDSPLAY_PRESET_BUTTON').' 1',
		'preset_2' => string('KIDSPLAY_PRESET_BUTTON').' 2',
		'preset_3' => string('KIDSPLAY_PRESET_BUTTON').' 3',
		'preset_4' => string('KIDSPLAY_PRESET_BUTTON').' 4',
		'preset_5' => string('KIDSPLAY_PRESET_BUTTON').' 5',
		'preset_6' => string('KIDSPLAY_PRESET_BUTTON').' 6',
	},
	'Receiver' => {
		'pause' => string('KIDSPLAY_BUTTON'),
	},
);
	
# initialize
sub initPlugin {
	if ( $callbackSet == 0 ) {
		# wait a few seconds to register hooks to better ensure that we wrap
		# the IR and button commands last
		Slim::Utils::Timers::setTimer('moot', (Time::HiRes::time() + 3), \&registerHooks);
		# init prefs
		&initPrefs();
		# register a CLI command
		Slim::Control::Request::addDispatch(['kidsplayvolume','_delta'], [1, 0, 0, \&volumeCLI]);
		Slim::Control::Request::addDispatch(['kidsplaytoggleclientpref','_prefname','_val1','_val2'], [1, 0, 0, \&toggleclientprefCLI]);
		Slim::Control::Request::addDispatch(['kidsplaymacro','_type', '_name', '_runall'], [1, 0, 0, \&macroCLI]);
		Slim::Control::Request::addDispatch(['kidsplaydumpmacros'], [0, 0, 0, \&macroDumpCLI]);
		Slim::Control::Request::addDispatch(['kidsplaydumpplayermacros'], [1, 0, 0, \&playerMacroDumpCLI]);
		Slim::Control::Request::addDispatch(['kidsplaymacroset'], [0, 0, 0, undef]);
		Slim::Control::Request::addDispatch(['kidsplayexec'], [0, 0, 0, \&execCLI]);
		if ( substr($::VERSION,0,3) lt 7.4 ) {
			Slim::Web::HTTP::protectCommand('kidsplayexec');
			Slim::Web::HTTP::protectCommand('kidsplayvolume');
			Slim::Web::HTTP::protectCommand('kidsplaytoggleclientpref');
			Slim::Web::HTTP::protectCommand('kidsplaymacro');
			Slim::Web::HTTP::protect('plugins\/KidsPlay\/settings\/global\.html\?.*\bKP_action\=');
			# the real global settings page
			Slim::Web::HTTP::addPageFunction("plugins/KidsPlay/settings/global.html", \&Plugins::KidsPlay::Web::handleWeb);
			Slim::Web::Pages->addPageLinks('plugins', { 'PLUGIN_KIDSPLAY_BASIC_SETTINGS' => 'plugins/KidsPlay/settings/global.html' });
		} else {
			if (!$::noweb) {
				Slim::Web::HTTP::CSRF->protectCommand('kidsplayexec'); 
				Slim::Web::HTTP::CSRF->protectCommand('kidsplayvolume'); 
				Slim::Web::HTTP::CSRF->protectCommand('kidsplaytoggleclientpref'); 
				Slim::Web::HTTP::CSRF->protectCommand('kidsplaymacro'); 
				Slim::Web::HTTP::CSRF->protect('plugins\/KidsPlay\/settings\/global\.html\?.*\bKP_action\=');
				Slim::Web::Pages->addPageFunction("plugins/KidsPlay/settings/global.html", \&Plugins::KidsPlay::Web::handleWeb);
				Slim::Web::Pages->addPageLinks('plugins', { 'PLUGIN_KIDSPLAY_BASIC_SETTINGS' => 'plugins/KidsPlay/settings/global.html' });
			}
		}
	}
	if (!$::noweb) {
		require Plugins::KidsPlay::PlayerSettings;
		#require Plugins::KidsPlay::GlobalSettings;
		require Plugins::KidsPlay::Web;
		# player settings
		Plugins::KidsPlay::PlayerSettings->new();
		# global settings (just a redir)
		#Plugins::KidsPlay::GlobalSettings->new();
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

sub execCLI {
        my $request = shift;
	# check this is the correct command.
	if ($request->isNotCommand([['kidsplayexec']])) {
		$request->setStatusBadDispatch();
		return;
	}
	my $execEnabled = $prefs->get("execEnabled");
	if (! &secretFileExists() ) {
		$log->warn("security: you must explicitly create a file named \"".&secretFileName()."\" on your server to use kidsplayexec");
		$request->setStatusBadDispatch();
		return;
	}
	# bail if no CSRF protection or not password protected
	if ( $execRequiresCRSFProtection ) {
		my $csrfProtection = $serverPrefs->get('csrfProtectionLevel');
		if ( $csrfProtection < 1 ) {
			$log->warn("security: you must set the CRSF Protection Level to Medium or High in order to use kidsplayexec");
			$request->setStatusBadDispatch();
			return;
		}
	}
	if ( $execRequiresPasswordProtection ) {
		my $passwordRequired = $serverPrefs->get('authorize');
		if ( $passwordRequired != 1 ) {
			$log->warn("security: you must require username/password authorization in order to use kidsplayexec");
			$request->setStatusBadDispatch();
			return;
		}
	}
	# get the parameters
	my $client = $request->client();
	my $val = $request->getParam('_p1');
	if ( (!defined($val)) || ($val ne $prefs->get("execSecret")) ) {
		$log->warn("security: incorrect secret value passed to kidsplayexec");
		$request->setStatusBadDispatch();
		return;
	}
	my @sysargs = ();
	my $n = 2;
	while ($n > 0) {
		my $val = $request->getParam('_p'.$n);
		if ( defined($val) ) {
			push @sysargs, $val;
			++$n;
		} else {
			$n = -1;
		}
	}
	if ( scalar(@sysargs) < 1 ) {
		$log->warn("kidsplayexec needs the proper secret and at least one command argument");
		$request->setStatusBadDispatch();
		return;
	}
	# invoke the command
	$log->debug("kidsplayexec executing ".join("\t",@sysargs));
	my $rc = system(@sysargs);
	$log->debug("kidsplayexec exitval: $rc");
	$request->addResult('exitval',$rc);
	$request->setStatusDone();
}


sub macroCLI {
        my $request = shift;
	# check this is the correct command.
	if ($request->isNotCommand([['kidsplaymacro']])) {
		$request->setStatusBadDispatch();
		return;
	}
	# get the parameters
	my $client = $request->client();
	my $type = $request->getParam('_type');
	my $name = $request->getParam('_name');
	my $runall = $request->getParam('_runall');
	# initialize client prefs
	&initClientPrefs($client);
	my $macro = &getMacro($name,$type,$client);
	if ( $macro =~ m/\S/ ) {
		$log->debug("we have a macro for $type - $name ; executing");
		&runMacro($client,$type,$name,$macro,$runall);
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
		if ( substr($::VERSION,0,3) ge '7.4' ) {
			# wrap button for Radio
			$originalButtonCommand = Slim::Control::Request::addDispatch(['button','_buttoncode','_time','_orFunction'],[1, 0, 0, \&KidsPlay_buttonCommand]);
			$originalJiveFavoritesCommand = Slim::Control::Request::addDispatch(['jivefavorites', '_cmd' ], [1, 0, 1, \&KidsPlay_jiveFavoritesCommand]);
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
	my $RcsVersion = '$Revision: 1.45 $';
	$RcsVersion =~ s/.*:\s*([0-9\.]*).*$/$1/;
	return $RcsVersion;
}

sub getDisplayName() {
	return 'PLUGIN_KIDSPLAY';
}

sub canUseKidsPlay($) {
	my $client = shift;
	return ( (! $client->isa("Slim::Player::SqueezePlay")) || ($client->model() eq 'baby') );
}

sub KidsPlay_jiveFavoritesCommand {
	my @args = @_;
	my $request = $args[0];
	my $client = $request->client();
	if (! defined($client) ) {
		$log->info("no client! calling original button command");
		return &$originalJiveFavoritesCommand(@args);
	}
	# not Radio? do regular thing
	my $cmd = $request->getParam('_cmd');
	my $key = $request->getParam('key');
	if ( ($client->model() ne 'baby') || ($cmd ne 'set_preset') || (! defined($key))  ) {
		$log->debug($client->name()." should use the IR handler");
		return &$originalJiveFavoritesCommand(@args);
	}
	my $type = 'Radio';
	my $pref = &behaviorPref($client,$type);
	if ( $pref eq 'PLUGIN_KIDSPLAY_CHOICE_NORMAL' ) {
		return &$originalJiveFavoritesCommand(@args);
	}
	my $buttoncode = 'preset_'.$key;
	my $macro = &getMacro($buttoncode,$type,$client);
	if ( $macro =~ m/\S/ ) {
		$log->debug("we have a macro for $type - $buttoncode");
		&runMacro($client,$type,$buttoncode,$macro,1);
		$request->setStatusDone();
		return;
	}
	if ($pref eq 'PLUGIN_KIDSPLAY_CHOICE_ONLY') { 
		$log->debug("no macro for $type - $buttoncode; doing nothing");
		$request->setStatusDone();
		return;
	}
	return &$originalJiveFavoritesCommand(@args);
}



sub KidsPlay_buttonCommand {
	my @args = @_;
	my $request = $args[0];
	my $buttoncode = $request->getParam('_buttoncode');
	my $client = $request->client();
	if (! defined($client) ) {
		$log->info("no client! calling original button command");
		return &$originalButtonCommand(@args);
	}
	# not Radio? do regular thing
	if ($client->model() ne 'baby' ) {
		$log->debug($client->name()." should use the IR handler");
		return &$originalButtonCommand(@args);
	}
	$buttoncode =~ s/\.single$//;
	my $type = 'Radio';
	my $pref = &behaviorPref($client,$type);
	if ( $pref eq 'PLUGIN_KIDSPLAY_CHOICE_NORMAL' ) {
		return &$originalButtonCommand(@args);
	}
	my $macro = &getMacro($buttoncode,$type,$client);
	if ( $macro =~ m/\S/ ) {
		$log->debug("we have a macro for $type - $buttoncode");
		&runMacro($client,$type,$buttoncode,$macro,1);
		$request->setStatusDone();
		return;
	}
	if ($pref eq 'PLUGIN_KIDSPLAY_CHOICE_ONLY') { 
		$log->debug("no macro for $type - $buttoncode; doing nothing");
		$request->setStatusDone();
		return;
	}
	return &$originalButtonCommand(@args);
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
	# remove down (Boom & Receiver macros are unqualified & we only act on down)
	$codename =~ s/\.down$//;
	my $type = undef;
	# following IFF jvc code:
	# Boom presets: 00010020-00010025 down, 00020020-00020025 up
	# Receiver: up=00020017, down=00010017
	if ( $ircode =~ m/^0000/) {
		$type = 'JVC';
	} elsif ( $ircode =~ m/^000[12]002[0-8]/) {
		$type = 'Boom';
	} elsif ( ($ircode =~ m/^000[12]0017/) && $client->isa( "Slim::Player::Receiver") ) {
		$type = 'Receiver';
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
	if (! &canUseKidsPlay($client) ) {
		$log->info($client->name()." cannot use KidsPlay");
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
	my $macro = &getMacro($codename,$type,$client);
	if ( $macro =~ m/\S/ ) {
		$log->debug("we have a macro for $type - $codename ; last execute $then last code $what now $now");
		$done = 1;
		if ( (!defined($then)) || (defined($what) && ($what ne $codename)) || (($now - $then) > $wait) ) {
			&runMacro($client,$type,$codename,$macro,1);
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

sub runMacro($$$$$) {
	my($client,$type,$codename,$macro,$runPrePost) = @_;
	# pre-macro?
	if ( $runPrePost ) {
		my $macro2 = &getMacro('pre','KP',$client);
		$macro2 =~ s/\;\s*$//s;
		if ( $macro2 =~ m/\S/ ) {
			&executeKidsPlay($client,'KP','pre',$macro2);
		}
	}
	&executeKidsPlay($client,$type,$codename,$macro);
	if ( $runPrePost ) {
		# post-macro?
		my $macro2 = &getMacro('post','KP',$client);
		$macro2 =~ s/\;\s*$//s;
		if ( $macro2 =~ m/\S/ ) {
			&executeKidsPlay($client,'KP','post',$macro2);
		}
	}
}

sub cleanMacro($) {
	my $macro = shift;
	$macro =~ s/^\s*//s;
	$macro =~ s/\;?\s*$//s;
	return $macro;
}

sub getMacro($$$) {
	my ($shortcode,$type,$client) = @_;
	# use global prefs for "macro-$type-$shortcode"
	my $macro = &cleanMacro($prefs->client($client)->get("macro-$type-$shortcode"));
	# use the player-specific macro if it is set
	if ( $macro ne '' ) { return $macro; }
	# otherwise grab the global macro
	return &cleanMacro($prefs->get("macro-$type-$shortcode"));
}

sub setExecSecret() {
	my $s = 10000000 + int(rand(89999999));
	$prefs->set("execSecret",$s);
}

sub secretFileName() {
	if ($^O =~ m/Win32/) {
		return 'c:\kidsplayexec.txt';
	}
	return '/kidsplayexec.txt';
}

sub secretFileExists() {
	if ( -f &secretFileName() ) {
		return 1;
	}
	return 0;
}

sub initPrefs(){
	my $waitJVC = $prefs->get("waitJVC");
	if ( (!defined($waitJVC)) || ($waitJVC eq '') ) {
		$prefs->set("waitJVC",$minWait);
		$prefs->set("waitBoom",0);
	}
	my $waitReceiver = $prefs->get("waitReceiver");
	if ( (!defined($waitReceiver)) || ($waitReceiver eq '') ) {
		$prefs->set("waitReceiver",0);
	}
	my $waitRadio= $prefs->get("waitRadio");
	if ( (!defined($waitRadio)) || ($waitRadio eq '') ) {
		$prefs->set("waitRadio",$minWait);
	}
	my $execEnabled = $prefs->get("execEnabled");
	if ( (!defined($execEnabled)) || ($execEnabled eq '') ) {
		$prefs->set("execEnabled",0);
	}
	my $execSecret = $prefs->get("execSecret");
	if ( (!defined($execSecret)) || ($execSecret eq '') ) {
		&setExecSecret();
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
		my @commands = &getCommands($client,$macro);
		foreach my $fieldPtr (@commands) {
			&addToQueue(@$fieldPtr);
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
		my $for = pop @cmdArgs;
		my $client = pop @cmdArgs;
		my $id = $client->id();
		my $fid = $for->id();
		my $fname = $for->name();
		$log->info("for client $id, execute \"".join('" "',@cmdArgs)."\" on $fid ($fname)");
		Slim::Control::Request::executeRequest($for, \@cmdArgs, undef, undef);
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
	# Receiver gets Boom behavior
	if ( $type eq 'Receiver' ) { $type = 'Boom'; }
	if ( $type eq 'Radio' ) { $type = 'Boom'; }
	return $prefs->client($client)->get("behavior${type}");
}	

# --------------------------------------------- macro-parsing routines -------------------------------

# input:
# 	calling $client
# 	string representing the macro, e.g. "OTHERS: power 0; power 1; mixer volume 10"
#
# output:
# 	array of command arrays, each of which ends with two client refs (issuing client, then context client)
# 	e.g. if the above macro was invoked by the "Bedroom" client against a server that also had Den and
# 	Kitchen players, getCommands() would return an array like
# 		[
# 			['power','0',$bedroomClient,$denClient],
# 			['power','0',$bedroomClient,$kitchenClient],
# 			['power','1',$bedroomClient,$bedroomClient],
# 			['mixer','volume','10',$bedroomClient,$bedroomClient],
# 		]
#
sub getCommands($$) {
	my $client = shift;
	my $macro = shift;
	$macro =~ s/[\;\s]*$//s;	# strip terminal chars
	my @commands;
	my @ms = &splitLines($macro,";");
	foreach my $m (@ms) {
		my @fields = &parseFields($m,$client);
		my @forWhom = &makePlayerList($client,\@fields);
		push @fields, $client;	# who invoked
		if ( scalar(@forWhom) > 0 )  {
			shift @fields;		# first field is the location indicator, not a command
			foreach my $p (@forWhom) {
				my @f = @fields;
				push @f, $p;	# context to run in
				push @commands, \@f;
			}
		} else {
			# the "for" client is also this client
			push @fields, $client;
			push @commands, \@fields;
		}
	}
	return @commands;
}

sub makePlayerList($$) {
	my $client = shift;
	my $cmdArgsPtr = shift;
	my @cmdArgs = @$cmdArgsPtr;
	my @clients = ();
	if ( (scalar(@cmdArgs) > 1) && (defined($client) && ( $client->isa("Slim::Player::Player") )) && (($cmdArgs[0] =~ m/^(.{1,}):$/) || ($cmdArgs[0] =~ m/^[0-9a-f]{2}\:[0-9a-f]{2}\:[0-9a-f]{2}\:[0-9a-f]{2}\:[0-9a-f]{2}\:[0-9a-f]{2}$/i))  ) {
		my $id = $client->id();
		my $which = $cmdArgs[0];
		shift @cmdArgs;
		$which =~ s/:$//;
		# *all* clients ( "ALL:" )
		if ( ($which eq 'ALL') || ($which eq 'OTHERS') ) {
			my $avoid = '';
			if ( $which eq 'OTHERS' ) {
				$avoid = $id;
			}
			# remove 'ALL:' or 'OTHERS:' (or specific ID)
			foreach my $p ( Slim::Player::Client::clients() ) {
				my $n = $p->name();
				my $i = $p->id();
				if ( ($n ne 'ALL') && ($n ne 'OTHERS') && ($i ne $avoid) ) {
					$log->info("for client $id, prepare to execute \"".join('" "',@cmdArgs)."\" for $i/$n");
					# add this player's object
					push @clients, $p;
				}
			}
		}
		# by MAC address ( "00:04:20:11:22:33:" )
		elsif ( $which =~ m/^[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}$/i ) {
 			my $c2 = Slim::Player::Client::getClient($which);
			if ( defined($c2) ) {
				$log->info("for client $id, prepare to execute \"".join('" "',@cmdArgs)."\" for $which");
				push @clients, $c2;
			} else {
				$log->warn("for client $id, cannot execute \"".join('" "',@cmdArgs)."\" for $which -- client not found");
			}
		}
		# by name? ( "Player Name:" )
		else {
			my $c2 = &getClientByName($which);
			if (defined($c2) ) {
				$log->info("for client $id, prepare to execute \"".join('" "',@cmdArgs)."\" for $which");
				push @clients, $c2;
			} else {
				$log->warn("for client $id, cannot execute \"".join('" "',@cmdArgs)."\" for $which -- client not found");
			}
		}
	}
	return @clients;
}

sub getClientByName($) {
	my $name = shift;
	my @players = Slim::Player::Client::clients();
	foreach my $client ( @players ) {
		if ( defined($client->name()) && ($name eq $client->name()) ) {
			return $client;
		}
	}
	return undef;
}

# --------------------------------------------- macro-parsing routines -------------------------------
sub getButtonHash($) {
	my $type = shift;
	my $hashPtr = $supportedButtons{$type};
	return $hashPtr;
}

sub dumpMacros() {
	my $whichClient = shift;
	my %info;
	Slim::Control::Request::notifyFromArray($whichClient, ['kidsplaymacrosetbegin']);
	foreach my $type (keys %supportedButtons) {
		my $infoHashPtr = &getButtonHash($type);
		foreach my $button (keys %$infoHashPtr) {
			my $thisMacro = $prefs->get("macro-${type}-$button");
			if (! defined($whichClient) ) {
				Slim::Control::Request::notifyFromArray(undef, ['kidsplaymacroset', $type, $button, $thisMacro]);
			} else {
				$info{"${type}\t${button}"} = $thisMacro;
			}
		}
		# loop through players & dump override macros
		my @players = Slim::Player::Client::clients();
		if ( defined($whichClient) ) { @players = [ $whichClient ]; }
		foreach my $client ( @players ) {
			foreach my $button (keys %$infoHashPtr) {
				my $thisMacro = $prefs->client($client)->get("macro-${type}-$button");
				if ( $thisMacro =~ m/\S/ ) {
					# has non-whitespace (something is here)
					if (! defined($whichClient) ) {
						Slim::Control::Request::notifyFromArray($client, ['kidsplaymacroset', $type, $button, $thisMacro]);
					} else {
						# overrides global
						$info{"${type}\t${button}"} = $thisMacro;
					}
				}
			}
		}
	}
	if ( defined($whichClient) ) {
		foreach my $k (keys %info) {
			my ($type,$button) = split(/\t/,$k);
			Slim::Control::Request::notifyFromArray($whichClient, ['kidsplaymacroset', $type, $button, $info{$k}]);
		}
	}
	Slim::Control::Request::notifyFromArray($whichClient, ['kidsplaymacrosetend']);
}

sub macroDumpCLI {
        my $request = shift;
	# check this is the correct command.
	if ($request->isNotCommand([['kidsplaydumpmacros']])) {
		$request->setStatusBadDispatch();
		return;
	}
	&dumpMacros();
	$request->setStatusDone();
}

sub playerMacroDumpCLI {
        my $request = shift;
	# check this is the correct command.
	if ($request->isNotCommand([['kidsplaydumpplayermacros']])) {
		$request->setStatusBadDispatch();
		return;
	}
	my $client = $request->client();
	&dumpMacros($client);
	$request->setStatusDone();
}
# --------------------------------------------- macro-parsing routines -------------------------------


# ------------------------------------------------  CLI parsing routines ---------------------------------------
# sub to handle quoted fields, e.g. 'playlist play "/path/with some spaces/playlist.m3u"'
sub parseFields($$) {
        my ($line,$client) = @_;
	# certain characters should be escaped with a \ :
	# 	\ ; " [ ] { }
	# if the \ char is followed by any other char,
	# \ and the char following are interpreted as 2 chars
	my $specialC = "\\;\"\[\]\{\}";
	$line =~ s/^\s*//;
	$line =~ s/\s*$//;
	my @cooked = ();
	my $in = 0;
	my $quoted = 0;
	my $escaped = 0;
	my $i = 0;
	my $word = '';
	while ($i < length($line) ) {
		my $c = substr($line,$i++,1);
		$escaped = 0;
		if ( $c eq "\\" ) {
			$escaped = 1;
			if ($i < (length($line) -1)) {
				my $c2 = substr($line,$i++,1);
				if (index($specialC,$c2) > -1) {
					$c = $c2;
				} else {
					--$i;
					$escaped = 0;
				}

			} else {
				# just a \
			}
		}
		if ( $in ) {
			if ( $escaped ) {
				$word .= $c;
			} else {
				# end of this word?
				if ( ($quoted && ($c eq '"')) || ((!$quoted) && ($c =~ /\s/)) ) {
					push @cooked, $word;
					$word = '';
					$in = 0;
					$quoted = 0;
				} else {
					# variable subst
					if ( $c eq '{' ) {
						# find the end of {this}
						my $end = index($line,'}',$i);
						if ( $end > $i ) {
							my $diff = $end - $i;
							# get the substitution
							my $varname = substr($line,$i,$diff);
							my $replace = &replaceVariable($varname,$client);
							# increment $i
							$i += $diff;
							++$i;
							# append subst to $word
							$word .= $replace;
						} else {
							$word .= $c;
						}
					} else {
						# build & keep moving
						$word .= $c;
					}
				}
			}
		} else {
			# look for delim
			if ( $c eq '"' ) {
				$quoted = 1;
				$in = 1;
			} elsif ( $c !~ /\s/ ) {
				$quoted = 0;
				$in = 1;
				--$i;		# move back and try again
				#$word .= $c;
			}
		}
	}
	if ( $in ) { push @cooked, $word; }
	return @cooked;
}

sub splitLines($$) {
	my $macro = shift;
	my $delim = shift;
	my @ms;
	my $line = '';
	my $i = 0;
	while ($i < length($macro) ) {
		my $c = substr($macro,$i,1);
		if ( $c eq "\\" ) {
			if ($i < (length($macro) -1)) {
				$c .= substr($macro,++$i,1);
			} else {
				# invalid escape!
				$c = '';
			}
		} else {
			if ($c eq $delim) {
				push @ms, $line;
				$line = '';
				$c = '';
			}
		}
		$line .= $c;
		++$i;
	}
	if ($line ne '') {
		push @ms, $line;
	}
	return @ms;
}

sub replaceVariable($$) {
	my ($name,$client) = @_;
	if (! defined($::VERSION) ) {
		if ( $name eq 'PLAYER_NAME' ) { return 'Master Bedroom'; }
		return "\$$name";
	}
	# actual logic for SC/SBS
	if ( $name eq 'PLAYER_NAME' ) { return $client->name(); }
	if ( $name eq 'PLAYER_ID' ) { return $client->id(); }
	if ( $name =~ m/^CURRENT_TRACK_/ ) {
		my $song = Slim::Player::Playlist::song($client);
		if ( $name eq 'CURRENT_TRACK_ALBUM' ) {
			return defined($song->album()) ? ( ref $song->album() ? $song->album()->name() : $song->album() ) : '';
		}
		if ( $name eq 'CURRENT_TRACK_ARTIST' ) {
        		return defined($song->artist()) ? ( ref $song->artist() ? $song->artist()->name(): $song->artist() ) : '';
		}
		if ( $name eq 'CURRENT_TRACK_TITLE' ) {
        		#return $song->name() || $song->{title} || $song->{desc} || '';
        		return $song->name() || $song->{title} || '';
		}
		if ( $name eq 'CURRENT_TRACK_ID' ) {
        		return $song->id() || '' ;
		}
	}
	return '';
}
# ------------------------------------------------  CLI parsing routines ---------------------------------------

1;

