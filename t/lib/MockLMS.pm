package MockLMS;

# Lightweight mocks for LMS dependencies so we can test plugin code in isolation.
# Load this BEFORE any Plugins::TIDAL::* modules:
#   use lib 't/lib';
#   use MockLMS;

use strict;
use warnings;

# --- CPAN module stubs (normally provided by LMS runtime) ---
BEGIN {
	# Exporter::Lite — just re-export via standard Exporter
	unless (eval { require Exporter::Lite; 1 }) {
		package Exporter::Lite;
		sub import {
			my $class = shift;
			my $caller = caller;
			# Make the calling package use standard Exporter
			no strict 'refs';
			push @{"${caller}::ISA"}, 'Exporter' unless grep { $_ eq 'Exporter' } @{"${caller}::ISA"};
		}
		$INC{'Exporter/Lite.pm'} = 1;
	}

	# JSON::XS::VersionOneAndTwo — provide from_json/to_json via JSON::PP
	unless (eval { require JSON::XS::VersionOneAndTwo; 1 }) {
		package JSON::XS::VersionOneAndTwo;
		require JSON::PP;
		sub import {
			my $caller = caller;
			no strict 'refs';
			*{"${caller}::from_json"} = \&JSON::PP::decode_json;
			*{"${caller}::to_json"} = \&JSON::PP::encode_json;
		}
		$INC{'JSON/XS/VersionOneAndTwo.pm'} = 1;
	}

	# Data::URIEncode
	unless (eval { require Data::URIEncode; 1 }) {
		package Data::URIEncode;
		use Exporter 'import';
		our @EXPORT_OK = qw(complex_to_query);
		sub complex_to_query { return '' }
		$INC{'Data/URIEncode.pm'} = 1;
	}

	# Async::Util
	unless (eval { require Async::Util; 1 }) {
		package Async::Util;
		$INC{'Async/Util.pm'} = 1;
	}

	# Date::Parse
	unless (eval { require Date::Parse; 1 }) {
		package Date::Parse;
		use Exporter 'import';
		our @EXPORT_OK = qw(str2time);
		sub str2time { return time() }
		$INC{'Date/Parse.pm'} = 1;
	}

	# URI::Escape
	unless (eval { require URI::Escape; 1 }) {
		package URI::Escape;
		use Exporter 'import';
		our @EXPORT_OK = qw(uri_escape_utf8 uri_escape uri_unescape);
		sub uri_escape_utf8 { return $_[0] }
		sub uri_escape { return $_[0] }
		sub uri_unescape { return $_[0] }
		$INC{'URI/Escape.pm'} = 1;
	}

	# Scalar::Util and MIME::Base64 are core — no stubs needed

	# HTTP::Status (for Settings.pm)
	unless (eval { require HTTP::Status; 1 }) {
		package HTTP::Status;
		use Exporter 'import';
		our @EXPORT_OK = qw(RC_MOVED_TEMPORARILY);
		sub RC_MOVED_TEMPORARILY { 302 }
		$INC{'HTTP/Status.pm'} = 1;
	}

	# Slim modules that get use'd at compile time by various plugin modules
	# Slim base classes — register in %INC, provide stubs for methods they offer
	for my $stub (
		'Slim::Networking::SimpleAsyncHTTP',
		'Slim::Networking::SimpleSyncHTTP',
		'Slim::Utils::Accessor',
		'Slim::Utils::Misc',
		'Slim::Utils::Timers',
		'Slim::Utils::Progress',
		'Slim::Music::Import',
		'Slim::Player::Protocols::HTTPS',
		'Slim::Player::ProtocolHandlers',
		'Slim::Plugin::OPMLBased',
		'Slim::Plugin::OnlineLibraryBase',
		'Slim::Web::Settings',
		'Slim::Web::HTTP',
		'Slim::Utils::Scanner::Remote',
		'Slim::Music::Info',
		'Slim::Player::ReplayGain',
		'Slim::Control::Request',
	) {
		(my $file = $stub) =~ s|::|/|g;
		$file .= '.pm';
		$INC{$file} = 1;
	}

	# Give base classes a version so `use base` doesn't complain about empty packages
	for my $base (qw(
		Slim::Plugin::OPMLBased
		Slim::Plugin::OnlineLibraryBase
		Slim::Player::Protocols::HTTPS
		Slim::Web::Settings
	)) {
		no strict 'refs';
		${"${base}::VERSION"} = '0.01';
	}
	no strict 'refs';
	*{'Slim::Utils::Misc::getTempDir'} = sub { '/tmp' };
	*{'Slim::Utils::Misc::fileURLFromPath'} = sub { "file://$_[0]" };
	*{'Slim::Utils::Accessor::mk_accessor'} = sub { };
	*{'Slim::Player::ProtocolHandlers::registerURLHandler'} = sub { };
	*{'Slim::Player::ProtocolHandlers::registerHandler'} = sub { };
	*{'Slim::Plugin::OPMLBased::initPlugin'} = sub { };
	*{'Slim::Plugin::OPMLBased::_pluginDataFor'} = sub { '' };
	*{'Slim::Web::HTTP::filltemplatefile'} = sub { '' };
	*{'Slim::Music::Info::setBitrate'} = sub { };
	*{'Slim::Music::Info::setDuration'} = sub { };
}

# --- Slim::Utils::Prefs ---
BEGIN {
	package Slim::Utils::Prefs;
	my %stores;

	sub new {
		my ($class, $namespace) = @_;
		$stores{$namespace} ||= {};
		return bless { ns => $namespace, data => $stores{$namespace} }, $class;
	}

	sub get {
		my ($self, $key) = @_;
		return $self->{data}{$key};
	}

	sub set {
		my ($self, $key, $val) = @_;
		$self->{data}{$key} = $val;
	}

	sub remove {
		my ($self, @keys) = @_;
		delete $self->{data}{$_} for @keys;
	}

	sub init {
		my ($self, $defaults) = @_;
		for my $k (keys %$defaults) {
			$self->{data}{$k} = $defaults->{$k} unless defined $self->{data}{$k};
		}
	}

	sub migrate { 1 }
	sub setChange { }
	sub setValidate { }
	sub client { $_[0] }

	sub preferences {
		my $ns = $_[0] || 'plugin.tidal';
		return Slim::Utils::Prefs->new($ns);
	}

	sub import {
		my $caller = caller;
		no strict 'refs';
		*{"${caller}::preferences"} = \&preferences;
	}

	$INC{'Slim/Utils/Prefs.pm'} = 1;
}

# --- Slim::Utils::Cache ---
BEGIN {
	package Slim::Utils::Cache;

	sub new {
		my ($class) = @_;
		return bless { data => {} }, $class;
	}

	sub get {
		my ($self, $key) = @_;
		return $self->{data}{$key};
	}

	sub set {
		my ($self, $key, $val, $ttl) = @_;
		$self->{data}{$key} = $val;
	}

	sub remove {
		my ($self, $key) = @_;
		delete $self->{data}{$key};
	}

	$INC{'Slim/Utils/Cache.pm'} = 1;
}

# --- Slim::Utils::Log ---
BEGIN {
	package Slim::Utils::Log;

	sub new { return bless {}, $_[0] }
	sub addLogCategory { return Slim::Utils::Log->new() }
	sub logger { return Slim::Utils::Log->new() }

	sub import {
		my $caller = caller;
		no strict 'refs';
		*{"${caller}::logger"} = \&logger;
	}

	for my $method (qw(debug info warn error is_debug is_info is_warn is_error logBacktrace)) {
		no strict 'refs';
		*{"Slim::Utils::Log::$method"} = sub { 0 };
	}

	$INC{'Slim/Utils/Log.pm'} = 1;
}

# --- Slim::Utils::Strings ---
BEGIN {
	package Slim::Utils::Strings;
	require Exporter;
	our @ISA = ('Exporter');
	our @EXPORT_OK = qw(string cstring);

	sub string { return $_[0] }
	sub cstring { return $_[1] || $_[0] }

	$INC{'Slim/Utils/Strings.pm'} = 1;
}

# --- Slim::Web::HTTP::CSRF ---
BEGIN {
	package Slim::Web::HTTP::CSRF;
	sub protectName { return $_[1] }
	sub protectURI { return $_[1] }
	$INC{'Slim/Web/HTTP/CSRF.pm'} = 1;
}

# --- Stub out main:: constants used in compile-time guards ---
BEGIN {
	no warnings 'once';
	*main::SCANNER = sub { 0 };
	*main::DEBUGLOG = sub { 0 };
	*main::INFOLOG = sub { 0 };
	*main::WEBUI = sub { 0 };
}

# --- Helper to reset prefs between tests ---
sub reset_prefs {
	my ($ns, %vals) = @_;
	$ns ||= 'plugin.tidal';
	my $prefs = Slim::Utils::Prefs->new($ns);
	%{$prefs->{data}} = %vals;
	return $prefs;
}

1;
