#!/usr/bin/perl
# Regression test: myMixes must source from /pages/my_collection_my_mixes
# (the Tidal-app endpoint) — not /mixes/daily/track — and must filter out
# VIDEO_DAILY_MIX entries (LMS has no video pipeline).
use strict;
use warnings;
use Test::More tests => 9;

use lib 't/lib';
use MockLMS;
use Plugins::TIDAL::API::Async;

# Synthetic page response mirroring the live /pages/my_collection_my_mixes
# shape: rows -> modules -> pagedList.items, where items carry mixType.
my $synthetic_page = {
    title => 'My Mix',
    rows  => [{
        modules => [{
            type => 'MIX_LIST',
            pagedList => {
                items => [
                    { id => 'disc-1',  title => 'My Daily Discovery', mixType => 'DISCOVERY_MIX',  subTitle => 'Songs by new and familiar artists' },
                    { id => 'daily-1', title => 'My Mix 1',           mixType => 'DAILY_MIX',      subTitle => 'Artist A, Artist B and more' },
                    { id => 'daily-2', title => 'My Mix 2',           mixType => 'DAILY_MIX',      subTitle => 'Artist C, Artist D and more' },
                    { id => 'vid-1',   title => 'My Video Mix 1',     mixType => 'VIDEO_DAILY_MIX', subTitle => 'Some artists' },
                    { id => 'vid-2',   title => 'My Video Mix 2',     mixType => 'VIDEO_DAILY_MIX', subTitle => 'Other artists' },
                ],
            },
        }],
    }],
};

# Capture _get invocations so we can assert the call site too.
my @get_calls;
{
    no warnings 'redefine';
    *Plugins::TIDAL::API::Async::_get = sub {
        my ($self, $url, $cb, $params) = @_;
        push @get_calls, { url => $url, params => $params };
        $cb->($synthetic_page);
    };
}

my $self = bless { client => undef, userId => 1 }, 'Plugins::TIDAL::API::Async';

my $result;
$self->myMixes(sub { $result = $_[0] });

# Call-site assertions: right endpoint, right query params.
is(scalar @get_calls, 1, 'myMixes made exactly one _get call');
is($get_calls[0]{url}, '/pages/my_collection_my_mixes',
    'myMixes hits /pages/my_collection_my_mixes (not /mixes/daily/track)');
is($get_calls[0]{params}{deviceType}, 'BROWSER',
    'deviceType=BROWSER is set (pages endpoint requires it)');
ok(exists $get_calls[0]{params}{locale}, 'locale is set');

# Result-shape assertions: flat list, video mixes filtered, others kept.
is(ref $result, 'ARRAY', 'callback received an array ref');
is(scalar @$result, 3, 'returns 3 items (2 VIDEO_DAILY_MIX filtered from 5)');

my @ids = map { $_->{id} } @$result;
is_deeply([sort @ids], [qw(daily-1 daily-2 disc-1)],
    'kept DISCOVERY_MIX + DAILY_MIX, dropped VIDEO_DAILY_MIX');

# Defensive: an empty page response should yield an empty list, not crash.
@get_calls = ();
{
    no warnings 'redefine';
    *Plugins::TIDAL::API::Async::_get = sub {
        my ($self, $url, $cb, $params) = @_;
        $cb->({});  # empty response — no rows key at all
    };
}

my $empty;
$self->myMixes(sub { $empty = $_[0] });
is(ref $empty, 'ARRAY', 'empty page response still yields an array ref');
is(scalar @$empty, 0, 'empty page response yields zero items');
