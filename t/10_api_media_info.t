#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 24;

use lib 't/lib';
use MockLMS;
use Plugins::TIDAL::API;

# --- LOSSLESS track (default quality=LOSSLESS, DASH off, Atmos off) ---
MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 0, enableAtmos => 0);
{
    my $item = { mediaMetadata => { tags => ['LOSSLESS'] } };
    my $r = Plugins::TIDAL::API::getMediaInfo($item);
    is($r->{format},      'flc',   'LOSSLESS: format=flc');
    is($r->{media_tag},   '[H]',   'LOSSLESS: media_tag=[H]');
    is($r->{sample_rate}, 44100,   'LOSSLESS: sample_rate=44100');
    is($r->{sample_size}, 16,      'LOSSLESS: sample_size=16');
    is($r->{channels},    2,       'LOSSLESS: channels=2');
}

# --- HIRES_LOSSLESS with DASH enabled ---
MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 1, enableAtmos => 0);
{
    my $item = { mediaMetadata => { tags => ['LOSSLESS', 'HIRES_LOSSLESS'] } };
    my $r = Plugins::TIDAL::API::getMediaInfo($item);
    is($r->{format},      'mpd',   'HIRES+DASH: format=mpd');
    is($r->{media_tag},   '[M]',   'HIRES+DASH: media_tag=[M]');
    is($r->{sample_rate}, 48000,   'HIRES+DASH: sample_rate=48000');
    is($r->{sample_size}, 24,      'HIRES+DASH: sample_size=24');
}

# --- DOLBY_ATMOS with Atmos enabled ---
MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 0, enableAtmos => 1);
{
    my $item = { mediaMetadata => { tags => ['DOLBY_ATMOS'] } };
    my $r = Plugins::TIDAL::API::getMediaInfo($item);
    is($r->{format},      'mp4',   'Atmos: format=mp4');
    is($r->{media_tag},   '[A]',   'Atmos: media_tag=[A]');
    is($r->{sample_rate}, 48000,   'Atmos: sample_rate=48000');
    is($r->{sample_size}, 24,      'Atmos: sample_size=24');
    is($r->{channels},    6,       'Atmos: channels=6');
}

# --- HIRES_LOSSLESS with DASH disabled falls through to LOSSLESS ---
MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 0, enableAtmos => 0);
{
    my $item = { mediaMetadata => { tags => ['LOSSLESS', 'HIRES_LOSSLESS'] } };
    my $r = Plugins::TIDAL::API::getMediaInfo($item);
    is($r->{format},    'flc',   'HIRES+DASH disabled: falls back to flc');
    is($r->{media_tag}, '[H]',   'HIRES+DASH disabled: media_tag=[H]');
}

# --- Missing tags (mediaMetadata => {tags => undef}) ---
{
    my $item = { mediaMetadata => { tags => undef } };
    my $r;
    ok(eval { $r = Plugins::TIDAL::API::getMediaInfo($item); 1 }, 'undef tags: no crash');
    is($r->{format}, 'flc', 'undef tags: returns default format');
}

# --- Empty tags array ---
{
    my $item = { mediaMetadata => { tags => [] } };
    my $r;
    ok(eval { $r = Plugins::TIDAL::API::getMediaInfo($item); 1 }, 'empty tags: no crash');
    is($r->{format},    'flc',   'empty tags: default format=flc');
    is($r->{media_tag}, '[H]',   'empty tags: default media_tag=[H]');
    is($r->{sample_rate}, 44100, 'empty tags: default sample_rate=44100');
    is($r->{sample_size}, 16,    'empty tags: default sample_size=16');
    is($r->{channels},    2,     'empty tags: default channels=2');
}
