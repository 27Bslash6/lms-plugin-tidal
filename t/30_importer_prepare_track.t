#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 9;

use lib 't/lib';
use MockLMS;

# Stub API::Sync before loading Importer (only needed at runtime, but safe to stub early)
BEGIN {
    package Plugins::TIDAL::API::Sync;
    sub getTrackData { return undef }
    $INC{'Plugins/TIDAL/API/Sync.pm'} = 1;
}

use Plugins::TIDAL::API;
use Plugins::TIDAL::Importer;

MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 0, enableAtmos => 0);
MockLMS::reset_prefs('server', splitList => ',');

my $album = {
    title          => 'Test Album',
    id             => 100,
    releaseDate    => '2024-06-15',
    cover          => 'http://example.com/cover.jpg',
    type           => 'ALBUM',
    numberOfVolumes => 1,
    added          => 1700000000,
};

my $track = {
    id            => 12345,
    title         => 'Test Track',
    duration      => 240,
    artist        => { id => 1, name => 'Test Artist' },
    artists       => [{ id => 1, name => 'Test Artist', type => 'MAIN' }],
    tracknum      => 3,
    disc          => 1,
    bpm           => 120,
    replayGain    => -6.5,
    peak          => 0.95,
    mediaMetadata => { tags => ['LOSSLESS'] },
};

my $result = Plugins::TIDAL::Importer::_prepareTrack($album, $track);

ok(defined $result,                                         '_prepareTrack returns a result');
like($result->{url},           qr{tidal://12345\.flc},     'url matches tidal://12345.flc');
is($result->{CONTENT_TYPE},    'flc',                      'CONTENT_TYPE is flc');
is($result->{LOSSLESS},        1,                          'LOSSLESS is 1');
is($result->{TITLE},           'Test Track',               'TITLE is correct');
is($result->{YEAR},            '2024',                     'YEAR extracted from releaseDate');
is($result->{BPM},             120,                        'BPM is 120');
is($result->{REPLAYGAIN_TRACK_GAIN}, -6.5,                 'REPLAYGAIN_TRACK_GAIN is -6.5');
is($result->{SECS},            240,                        'SECS (duration) is 240');
