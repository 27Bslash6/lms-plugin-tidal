#!/usr/bin/perl
# Regression test: savedMixes must source the user's explicitly-saved mixes
# from /v2/my-collection/mixes (a different surface from the algorithmic
# /pages/my_collection_my_mixes that myMixes uses). Items are wrapped
# {data: {...}, addedAt, ...} — unwrap to the inner mix object so
# _renderMix can use it directly. Cursor pagination: follow until empty.
use strict;
use warnings;
use Test::More tests => 13;

use lib 't/lib';
use MockLMS;
use Plugins::TIDAL::API::Async;

sub mk_item {
    my ($id, $mix_type, $title, $sub) = @_;
    return {
        itemType => 'MIX',
        addedAt  => '2026-05-13T04:10:14.221+0000',
        data => {
            id       => $id,
            mixType  => $mix_type,
            title    => $title,
            subTitle => $sub,
        },
    };
}

# --- Case 1: single page, no cursor ---
my @get_calls;
{
    no warnings 'redefine';
    *Plugins::TIDAL::API::Async::_get = sub {
        my ($self, $url, $cb, $params) = @_;
        push @get_calls, { url => $url, params => $params };
        $cb->({
            items => [
                mk_item('aaa', 'TRACK_MIX',  'Govindam',     'Matthew E. White, Flo Morrissey'),
                mk_item('bbb', 'ARTIST_MIX', 'Eli Keszler',  'Artist Radio'),
            ],
            cursor => undef,
        });
    };
}

my $self = bless { client => undef, userId => 1 }, 'Plugins::TIDAL::API::Async';

my $result;
$self->savedMixes(sub { $result = $_[0] });

is(scalar @get_calls, 1, 'single-page response makes one _get call');
like($get_calls[0]{url}, qr{^https?://api\.tidal\.com/v2/my-collection/mixes$},
    'hits absolute /v2/my-collection/mixes URL (bypasses BURL/v1)');
ok(!exists $get_calls[0]{params}{cursor}, 'first call has no cursor param');
is($get_calls[0]{params}{limit}, 50, 'limit=50 passed');
ok($get_calls[0]{params}{_personal}, '_personal flag set (per-user cache)');

is(ref $result, 'ARRAY', 'callback received an array ref');
is(scalar @$result, 2, 'returns 2 items');
is($result->[0]{title}, 'Govindam', 'first item unwrapped: data.title flattened to title');
is($result->[0]{mixType}, 'TRACK_MIX', 'data.mixType flattened too');
is($result->[1]{title}, 'Eli Keszler', 'ARTIST_MIX entry preserved');

# --- Case 2: cursor pagination — two pages ---
@get_calls = ();
my @pages = (
    {
        items  => [ mk_item('p1a', 'TRACK_MIX', 'Page1A', 'a1') ],
        cursor => 'CURSOR_FOR_PAGE_2',
    },
    {
        items  => [ mk_item('p2a', 'TRACK_MIX', 'Page2A', 'a2'),
                    mk_item('p2b', 'TRACK_MIX', 'Page2B', 'a3') ],
        cursor => undef,
    },
);
{
    no warnings 'redefine';
    *Plugins::TIDAL::API::Async::_get = sub {
        my ($self, $url, $cb, $params) = @_;
        push @get_calls, { url => $url, params => $params };
        my $page = shift @pages;
        $cb->($page);
    };
}

my $paged;
$self->savedMixes(sub { $paged = $_[0] });

is(scalar @get_calls, 2, 'cursor pagination triggered 2 _get calls');
is($get_calls[1]{params}{cursor}, 'CURSOR_FOR_PAGE_2',
    'second call carries cursor from first response');
is(scalar @$paged, 3, 'aggregated 1+2 items across both pages');
