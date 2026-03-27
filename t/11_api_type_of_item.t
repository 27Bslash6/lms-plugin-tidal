#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 9;

use lib 't/lib';
use MockLMS;
use Plugins::TIDAL::API;

MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 0, enableAtmos => 0);

# --- Album ---
{
    my $item = { type => 'ALBUM', releaseDate => '2024-01-01', numberOfTracks => 12 };
    is(Plugins::TIDAL::API->typeOfItem($item), 'album', 'ALBUM type hash => album');
}

# --- Track ---
{
    my $item = { duration => 240 };
    is(Plugins::TIDAL::API->typeOfItem($item), 'track', 'duration-only hash => track');
}

# --- Artist ---
{
    my $item = { name => 'Test Artist' };
    is(Plugins::TIDAL::API->typeOfItem($item), 'artist', 'name-only hash => artist');
}

# --- Playlist ---
{
    my $item = { type => 'USER', numberOfTracks => 5, created => '2024-01-01' };
    is(Plugins::TIDAL::API->typeOfItem($item), 'playlist', 'USER type with numberOfTracks+created => playlist');
}

# --- Undef input ---
{
    is(Plugins::TIDAL::API->typeOfItem(undef), '', 'undef input => empty string');
}

# --- Empty hash: no type, no duration, no name => falls through to track ---
{
    my $item = {};
    is(Plugins::TIDAL::API->typeOfItem($item), 'track', 'empty hash => track (duration check: !type)');
}

# --- String input (non-ref) ---
{
    is(Plugins::TIDAL::API->typeOfItem('foo'), '', 'string input => empty string');
}

# --- EP type ---
{
    my $item = { type => 'EP', releaseDate => '2023-05-01', numberOfTracks => 4 };
    is(Plugins::TIDAL::API->typeOfItem($item), 'album', 'EP type => album');
}

# --- SINGLE type ---
{
    my $item = { type => 'SINGLE', releaseDate => '2024-03-01', numberOfTracks => 1 };
    is(Plugins::TIDAL::API->typeOfItem($item), 'album', 'SINGLE type => album');
}
