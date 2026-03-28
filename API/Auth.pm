package Plugins::TIDAL::API::Auth;

use strict;
use Data::URIEncode qw(complex_to_query);
use JSON::XS::VersionOneAndTwo;
use MIME::Base64 qw(encode_base64 decode_base64);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

use Plugins::TIDAL::API qw(AURL SCOPES GRANT_TYPE_DEVICE);

use constant TOKEN_PATH => '/v1/oauth2/token';

my $cache = Slim::Utils::Cache->new();
my $log = logger('plugin.tidal');
my $prefs = preferences('plugin.tidal');

my (%deviceCodes, $cid, $sec);

sub init {
	my $class = shift;
	
	# check if we are using custom cid and sec
	if ($prefs->get('enableCustomClientIDSecret')) {
		$cid = $prefs->get('custom_cid');
		$sec = $prefs->get('custom_sec');
		main::DEBUGLOG && $log->is_debug && $log->debug("Using custom client credentials");
	}
	else {
		$cid = $prefs->get('cid');
		$sec = $prefs->get('sec');
	}
	
	if (!$cid || !$sec) {
		$log->warn("Custom credentials enabled but empty - falling back to defaults")
			if $prefs->get('enableCustomClientIDSecret');
		$class->_fetchKs(<DATA>);
	}
}

sub initDeviceFlow {
	my ($class, $cb) = @_;

	$class->_call('/v1/oauth2/device_authorization', $cb, {
		scope => SCOPES
	});
}

sub pollDeviceAuth {
	my ($class, $args, $cb) = @_;

	my $deviceCode = $args->{deviceCode} || return $cb->();

	$deviceCodes{$deviceCode} ||= $args;
	$args->{expiry} ||= time() + $args->{expiresIn};
	$args->{cb}     ||= $cb if $cb;

	_delayedPollDeviceAuth($deviceCode, $args);
}

sub _delayedPollDeviceAuth {
	my ($deviceCode, $args) = @_;

	Slim::Utils::Timers::killTimers($deviceCode, \&_delayedPollDeviceAuth);

	if ($deviceCodes{$deviceCode} && time() <= $args->{expiry}) {
		__PACKAGE__->_call(TOKEN_PATH, sub {
			my $result = shift;

			if ($result) {
				if ($result->{error}) {
					Slim::Utils::Timers::setTimer($deviceCode, time() + ($args->{interval} || 2), \&_delayedPollDeviceAuth, $args);
					return;
				}
				else {
					_storeTokens($result)
				}

				delete $deviceCodes{$deviceCode};
			}

			$args->{cb}->($result) if $args->{cb};
		},{
			scope => SCOPES,
			grant_type => GRANT_TYPE_DEVICE,
			device_code => $deviceCode,
		});

		return;
	}

	# we have timed out
	main::INFOLOG && $log->is_info && $log->info("we have timed out polling for an access token");
	delete $deviceCodes{$deviceCode};

	return $args->{cb}->() if $args->{cb};

	$log->error('no callback defined?!?');
}

sub cancelDeviceAuth {
	my ($class, $deviceCode) = @_;

	return unless $deviceCode;

	Slim::Utils::Timers::killTimers($deviceCode, \&_delayedPollDeviceAuth);
	delete $deviceCodes{$deviceCode};
}

sub _fetchKs {
	my ($class, $data) = @_;

	($cid, $sec) = @{from_json(decode_base64(($data =~ s/[\x24\x2e]//gr) . '=' x 2))};
	$prefs->set('cid', $cid);
	$prefs->set('sec', $sec);
}

sub refreshToken {
	my ( $class, $cb, $userId ) = @_;

	my $accounts = $prefs->get('accounts') || {};
	my $profile  = $accounts->{$userId};

	if ( $profile && (my $refreshToken = $profile->{refreshToken}) ) {
		$class->_call(TOKEN_PATH, sub {
			$cb->(_storeTokens(@_));
		},{
			grant_type => 'refresh_token',
			refresh_token => $refreshToken,
		});
	}
	else {
		$log->error('Did find neither access nor refresh token. Please re-authenticate.');
		# TODO expose warning on client
		$cb->();
	}
}

sub _storeTokens {
	my ($result) = @_;

	if ($result->{user} && $result->{user_id} && $result->{access_token}) {
		my $accounts = $prefs->get('accounts');

		my $userId = $result->{user_id};

		# have token expire a little early
		$cache->set("tidal_at_$userId", $result->{access_token}, $result->{expires_in} - 300);

		$result->{user}->{refreshToken} = $result->{refresh_token} if $result->{refresh_token};
		my %account = (%{$accounts->{$userId} || {}}, %{$result->{user}});
		$accounts->{$userId} = \%account;

		$prefs->set('accounts', $accounts);
	}

	return $result->{access_token};
}

sub refreshTokenSync {
	my ( $class, $userId ) = @_;

	my $accounts = $prefs->get('accounts') || {};
	my $profile  = $accounts->{$userId};

	if ( $profile && (my $refreshToken = $profile->{refreshToken}) ) {
		my $cid_local = $prefs->get('custom_cid') || $prefs->get('cid');
		my $sec_local = $prefs->get('custom_sec') || $prefs->get('sec');

		return unless $cid_local && $sec_local;

		my $bearer = encode_base64(sprintf('%s:%s', $cid_local, $sec_local));
		$bearer =~ s/\s//g;

		my $params = {
			client_id    => $cid_local,
			grant_type   => 'refresh_token',
			refresh_token => $refreshToken,
		};

		my $response = Slim::Networking::SimpleSyncHTTP->new({
			timeout => 15,
		})->post(AURL . TOKEN_PATH,
			'Content-Type' => 'application/x-www-form-urlencoded',
			'Authorization' => 'Basic ' . $bearer,
			complex_to_query($params),
		);

		if ($response->code == 200) {
			my $result = eval { from_json($response->content) };
			if ($result && !$@) {
				main::INFOLOG && $log->is_info && $log->info("Sync token refresh successful for $userId");
				return _storeTokens($result);
			}
		}

		$log->error("Sync token refresh failed for $userId: " . ($response->code || 'unknown'));
	}
	else {
		$log->error('No refresh token available. Please re-authenticate.');
	}

	return;
}

sub _call {
	my ( $class, $url, $cb, $params ) = @_;

	my $bearer = encode_base64(sprintf('%s:%s', $cid, $sec));
	$bearer =~ s/\s//g;

	$params->{client_id} ||= $cid;

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;

			my $result = eval { from_json($response->content) };

			$@ && $log->error($@);
			main::INFOLOG && $log->is_info && $log->info("Auth response: user_id=$result->{user_id}, expires_in=$result->{expires_in}") if $result;

			$cb->($result);
		},
		sub {
			my ($http, $error) = @_;

			$log->error("Error: $error");
			main::INFOLOG && $log->is_info && $log->info("Auth error status: " . ($http->code || 'unknown'));

			$cb->({
				error => $error || 'failed auth request'
			});
		},
		{
			timeout => 15,
			cache => 0,
			expiry => 0,
		}
	)->post(AURL . $url,
		'Content-Type' => 'application/x-www-form-urlencoded',
		'Authorization' => 'Basic ' . $bearer,
		complex_to_query($params),
	);
}

1;

__DATA__
$WyJmWDJK$.$eGRtbnRaV0swaXhUIiwiMU5uOUFmREFq$.$eHJnSkZKYktOV0xlQXlLR1ZHbUlOdVhQ$.$UExIVlhBdnhBZz0iXQ$
