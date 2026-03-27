#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 13;

use lib 't/lib';
use MockLMS;
use Plugins::TIDAL::Plugin;

MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 0, enableAtmos => 0);

# =============================================================================
# _renderAlbum
# =============================================================================

my $item = {
    id             => 100,
    title          => 'Test Album',
    releaseDate    => '2024-06-15',
    explicit       => 0,
    numberOfTracks => 10,
    artist         => { id => 1, name => 'Test Artist' },
    mediaMetadata  => { tags => ['LOSSLESS'] },
};

my $result = Plugins::TIDAL::Plugin::_renderAlbum($item, 0);

ok(defined $result,                                     '_renderAlbum returns a result');
like($result->{name}, qr/2024/,                         'name includes release year');
like($result->{name}, qr/\[H\]/,                        'name includes quality tag [H]');
unlike($result->{name}, qr/\[E\]/,                      'no [E] for non-explicit album');

# Source title NOT mutated
is($item->{title}, 'Test Album',                        'source title not mutated after _renderAlbum');

# With explicit flag
my $explicit_item = {
    %$item,
    title    => 'Test Album',
    explicit => 1,
};
my $explicit_result = Plugins::TIDAL::Plugin::_renderAlbum($explicit_item, 0);
like($explicit_result->{name}, qr/\[E\]/,               'explicit album name includes [E]');

# Source title NOT mutated after explicit test
is($explicit_item->{title}, 'Test Album',               'source title not mutated after explicit test');

# With addArtistToTitle
my $artist_result = Plugins::TIDAL::Plugin::_renderAlbum($item, 1);
like($artist_result->{name}, qr/Test Artist/,            'addArtistToTitle: name includes artist');

# Source title not mutated after artist test
is($item->{title}, 'Test Album',                        'source title not mutated after artist test');

# =============================================================================
# _renderTrack
# =============================================================================

my $track_item = {
    id            => 12345,
    title         => 'Test Track',
    duration      => 240,
    explicit      => 0,
    artist        => { id => 1, name => 'Test Artist' },
    mediaMetadata => { tags => ['LOSSLESS'] },
};

my $track_result = Plugins::TIDAL::Plugin::_renderTrack($track_item, 0);

ok(defined $track_result,                               '_renderTrack returns a result');
like($track_result->{url}, qr{tidal://12345\.flc},      'url matches tidal://12345.flc');
is($track_result->{type},  'audio',                     'type is audio');

# explicit track test
my $explicit_track = { %$track_item, title => 'Test Track', explicit => 1 };
Plugins::TIDAL::Plugin::_renderTrack($explicit_track, 0);

# Source title NOT mutated after explicit test
is($track_item->{title}, 'Test Track',                  'track source title not mutated after explicit test');
