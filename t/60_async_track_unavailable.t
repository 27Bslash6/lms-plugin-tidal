#!/usr/bin/perl
# Regression test: stale playlists pointing at removed Tidal tracks must not
# re-hammer /tracks/$id and /tracks/$id/playbackinfopostpaywall on every play.
# A 404 (track gone) or 401 on playbackinfo (asset not ready) marks the ID
# unavailable for 24h; subsequent getTrackUrl calls short-circuit.
use strict;
use warnings;
use Test::More tests => 6;

use lib 't/lib';
use MockLMS;
use Plugins::TIDAL::API::Async;

# Reset the shared Slim::Utils::Cache instance backing the unavail keys.
my $cache = Slim::Utils::Cache->new();
%{$cache->{data}} = ();

# 1. Round-trip helpers
ok(!Plugins::TIDAL::API::Async::_isUnavailable(12345), 'unmarked ID is available');
Plugins::TIDAL::API::Async::_markUnavailable(12345);
ok(Plugins::TIDAL::API::Async::_isUnavailable(12345), 'marked ID is unavailable');

# Defensive: undef/empty IDs never trip the cache
ok(!Plugins::TIDAL::API::Async::_isUnavailable(undef), 'undef ID is not unavailable');
ok(!Plugins::TIDAL::API::Async::_isUnavailable(''),    'empty ID is not unavailable');

# 2. getTrackUrl short-circuits when the ID is cached unavailable —
#    must not reach the HTTP layer.
{
    no warnings 'redefine';
    local *Plugins::TIDAL::API::Async::_get = sub {
        die "FORBIDDEN: getTrackUrl made an HTTP call for an unavailable track\n";
    };

    my $self = bless { client => undef, userId => 1 }, 'Plugins::TIDAL::API::Async';
    my $called_cb = 0;
    eval {
        $self->getTrackUrl(sub { $called_cb = 1; }, 12345, {});
    };
    ok(!$@, "getTrackUrl did not hit _get for cached unavailable track")
        or diag("Error: $@");
    ok($called_cb, 'getTrackUrl invoked the error callback synchronously');
}
