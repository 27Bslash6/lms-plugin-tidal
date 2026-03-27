#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 23;
use Scalar::Util qw(reftype);

use lib 't/lib';
use MockLMS;
use Plugins::TIDAL::API::Async;

MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 1, enableAtmos => 0, preferExplicit => 0);

sub make_album {
    my (%args) = @_;
    return {
        artist        => { id => $args{artist_id} || 1 },
        title         => $args{title} || 'Test Album',
        numberOfTracks => $args{tracks} || 10,
        explicit      => $args{explicit} || 0,
        mediaMetadata => { tags => $args{tags} || ['LOSSLESS'] },
    };
}

# =============================================================================
# _tagAlbums
# =============================================================================

# LOSSLESS always gets rank 1
{
    my $album = make_album(tags => ['LOSSLESS']);
    my $tagged = Plugins::TIDAL::API::Async::_tagAlbums([$album]);
    is(scalar @$tagged, 1, '_tagAlbums: LOSSLESS album kept');
    is($tagged->[0]{_quality_rank}, 1, '_tagAlbums: LOSSLESS rank=1');
}

# HIRES_LOSSLESS with DASH enabled gets rank 2
{
    my $album = make_album(tags => ['LOSSLESS', 'HIRES_LOSSLESS']);
    my $tagged = Plugins::TIDAL::API::Async::_tagAlbums([$album]);
    is(scalar @$tagged, 1, '_tagAlbums: HIRES_LOSSLESS+DASH kept');
    is($tagged->[0]{_quality_rank}, 2, '_tagAlbums: HIRES_LOSSLESS+DASH rank=2');
}

# HIRES_LOSSLESS with DASH disabled gets rank 0 (excluded)
{
    MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 0, enableAtmos => 0);
    my $album = make_album(tags => ['LOSSLESS', 'HIRES_LOSSLESS']);
    my $tagged = Plugins::TIDAL::API::Async::_tagAlbums([$album]);
    # HIRES_LOSSLESS with DASH off: media_tag=[H] so rank=1, not excluded
    # (it falls through to LOSSLESS CD quality)
    is($tagged->[0]{_quality_rank}, 1, '_tagAlbums: HIRES_LOSSLESS+DASH disabled => rank=1 (CD)');
    MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 1, enableAtmos => 0, preferExplicit => 0);
}

# Album with no LOSSLESS/DOLBY_ATMOS tag is excluded entirely
{
    my $album = make_album(tags => ['HIGH']);
    my $tagged = Plugins::TIDAL::API::Async::_tagAlbums([$album]);
    is(scalar @$tagged, 0, '_tagAlbums: no LOSSLESS tag => excluded');
}

# =============================================================================
# _groupByFingerprint
# =============================================================================

{
    my $a1 = { album => make_album(title => 'Alpha'), _quality_rank => 1, _fingerprint => '1:Alpha:10' };
    my $a2 = { album => make_album(title => 'Beta'),  _quality_rank => 1, _fingerprint => '1:Beta:10'  };
    my $a3 = { album => make_album(title => 'Alpha'), _quality_rank => 2, _fingerprint => '1:Alpha:10' };

    my $result = Plugins::TIDAL::API::Async::_groupByFingerprint([$a1, $a2, $a3]);
    ok(exists $result->{groups},                     '_groupByFingerprint: has groups key');
    ok(exists $result->{order},                      '_groupByFingerprint: has order key');
    is(scalar @{ $result->{order} }, 2,              '_groupByFingerprint: 2 distinct fingerprints');
    is($result->{order}->[0], '1:Alpha:10',          '_groupByFingerprint: insertion order preserved (Alpha first)');
    is(scalar @{ $result->{groups}{'1:Alpha:10'} }, 2, '_groupByFingerprint: Alpha group has 2 entries');
}

# =============================================================================
# _selectPreferred
# =============================================================================

{
    # rank 1 and rank 2 same fingerprint => only rank 2 kept
    my $fp = '1:Test:10';
    my $a_low  = { album => make_album(), _quality_rank => 1, _fingerprint => $fp };
    my $a_high = { album => make_album(), _quality_rank => 2, _fingerprint => $fp };
    my $groups = Plugins::TIDAL::API::Async::_groupByFingerprint([$a_low, $a_high]);
    my $selected = Plugins::TIDAL::API::Async::_selectPreferred($groups);
    my ($sel_groups, $sel_order) = @{$selected}{qw(groups order)};
    is(scalar @{$sel_groups->{$fp}}, 1, '_selectPreferred: only highest rank kept');
    is($sel_groups->{$fp}->[0]{_quality_rank}, 2, '_selectPreferred: kept item has rank 2');
}

{
    # same rank => both kept
    my $fp = '1:Test:10';
    my $a1 = { album => make_album(explicit => 1), _quality_rank => 1, _fingerprint => $fp };
    my $a2 = { album => make_album(explicit => 0), _quality_rank => 1, _fingerprint => $fp };
    my $groups = Plugins::TIDAL::API::Async::_groupByFingerprint([$a1, $a2]);
    my $selected = Plugins::TIDAL::API::Async::_selectPreferred($groups);
    my ($sel_groups) = @{$selected}{qw(groups)};
    is(scalar @{$sel_groups->{$fp}}, 2, '_selectPreferred: same rank keeps both');
}

# =============================================================================
# _filterExplicit
# =============================================================================

{
    # preferExplicit=0, both versions exist => clean returned
    my $fp = '1:Test:10';
    my $explicit = { album => make_album(explicit => 1), _quality_rank => 1, _fingerprint => $fp };
    my $clean    = { album => make_album(explicit => 0), _quality_rank => 1, _fingerprint => $fp };
    my $data = Plugins::TIDAL::API::Async::_groupByFingerprint([$explicit, $clean]);
    my $result = Plugins::TIDAL::API::Async::_filterExplicit($data, 0);
    is(scalar @$result, 1, '_filterExplicit(prefer clean): one result');
    is($result->[0]{explicit}, 0, '_filterExplicit(prefer clean): clean version returned');
}

{
    # preferExplicit=1, both versions exist => explicit returned
    my $fp = '1:Test:10';
    my $explicit = { album => make_album(explicit => 1), _quality_rank => 1, _fingerprint => $fp };
    my $clean    = { album => make_album(explicit => 0), _quality_rank => 1, _fingerprint => $fp };
    my $data = Plugins::TIDAL::API::Async::_groupByFingerprint([$explicit, $clean]);
    my $result = Plugins::TIDAL::API::Async::_filterExplicit($data, 1);
    is(scalar @$result, 1, '_filterExplicit(prefer explicit): one result');
    is($result->[0]{explicit}, 1, '_filterExplicit(prefer explicit): explicit version returned');
}

{
    # only one version exists => returned regardless of preference
    my $fp = '1:Test:10';
    my $only = { album => make_album(explicit => 1), _quality_rank => 1, _fingerprint => $fp };
    my $data = Plugins::TIDAL::API::Async::_groupByFingerprint([$only]);

    my $r0 = Plugins::TIDAL::API::Async::_filterExplicit($data, 0);
    is(scalar @$r0, 1,               '_filterExplicit(only explicit, prefer clean): still returned');

    my $r1 = Plugins::TIDAL::API::Async::_filterExplicit($data, 1);
    is(scalar @$r1, 1,               '_filterExplicit(only explicit, prefer explicit): returned');
}

# =============================================================================
# Integration: full pipeline via _filterAlbums mock via _tagAlbums+pipeline
# =============================================================================

{
    # DASH enabled. Same title/artist/tracks in [H] (LOSSLESS) and [M] (HIRES_LOSSLESS).
    # Pipeline should keep only [M] version.
    MockLMS::reset_prefs('plugin.tidal', quality => 'LOSSLESS', enableDASH => 1, enableAtmos => 0, preferExplicit => 0);

    my $lossless = make_album(artist_id => 5, title => 'Big Album', tracks => 12, tags => ['LOSSLESS']);
    my $hires    = make_album(artist_id => 5, title => 'Big Album', tracks => 12, tags => ['LOSSLESS', 'HIRES_LOSSLESS']);

    my $tagged   = Plugins::TIDAL::API::Async::_tagAlbums([$lossless, $hires]);
    my $groups   = Plugins::TIDAL::API::Async::_groupByFingerprint($tagged);
    my $selected = Plugins::TIDAL::API::Async::_selectPreferred($groups);
    my $final    = Plugins::TIDAL::API::Async::_filterExplicit($selected, 0);

    is(scalar @$final, 1, 'integration: only one album returned after pipeline');
    is($final->[0]{mediaMetadata}{tags}[0], 'LOSSLESS',         'integration: result has LOSSLESS tag');
    ok((grep { $_ eq 'HIRES_LOSSLESS' } @{$final->[0]{mediaMetadata}{tags}}), 'integration: result is the HIRES version');
}
