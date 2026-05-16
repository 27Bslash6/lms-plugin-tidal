#!/usr/bin/perl
# Regression test: scanner must NOT call /playbackinfopostpaywall.
# That endpoint was the root cause of the 429 storm fixed in 1.10.5.
# If _prepareTrack ever re-introduces the call, this test fails loudly.
use strict;
use warnings;
use Test::More tests => 2;

use lib 't/lib';
use MockLMS;

# Stub API::Sync before loading Importer. Override _get so any call whose URL
# contains /playbackinfopostpaywall explodes, making the forbidden call obvious.
BEGIN {
    package Plugins::TIDAL::API::Sync;
    sub _get {
        my (undef, $url) = @_;
        if ($url && $url =~ m{playbackinfopostpaywall}) {
            die "FORBIDDEN: _prepareTrack called playbackinfopostpaywall ($url)\n";
        }
        return {};
    }
    $INC{'Plugins/TIDAL/API/Sync.pm'} = 1;
}

use Plugins::TIDAL::API;
use Plugins::TIDAL::Importer;

MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 0, enableAtmos => 0);
MockLMS::reset_prefs('server', splitList => ',');

my $album = {
    title           => 'Regression Album',
    id              => 200,
    releaseDate     => '2023-01-01',
    cover           => 'http://example.com/cover.jpg',
    type            => 'ALBUM',
    numberOfVolumes => 1,
    added           => 1700000000,
};

my $track = {
    id            => 99999,
    title         => 'Regression Track',
    duration      => 180,
    artist        => { id => 1, name => 'Test Artist' },
    artists       => [{ id => 1, name => 'Test Artist', type => 'MAIN' }],
    tracknum      => 1,
    disc          => 1,
    bpm           => 100,
    replayGain    => -5.0,
    peak          => 0.99,
    mediaMetadata => { tags => ['LOSSLESS'] },
};

my $result = eval { Plugins::TIDAL::Importer::_prepareTrack($album, $track) };
ok(!$@, "_prepareTrack completed without calling playbackinfopostpaywall") or diag("Error: $@");
ok(defined $result, '_prepareTrack returned a result');
