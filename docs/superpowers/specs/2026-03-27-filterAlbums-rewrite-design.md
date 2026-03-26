# _filterAlbums Rewrite: Group-Select-Filter Pipeline

## Problem

`_filterAlbums` in `API/Async.pm` is a single function doing five things via a tangled `grep { } map { }` with mutable state shared across closures. It's nearly impossible to reason about, debug, or extend. See issue #9 for the full analysis.

## Goal

Replace with a pipeline of three named subs, each with one responsibility. Rethink the deduplication algorithm to use user-preferred quality with fallback. Simplify explicit handling from a 3-way per-user hash to a boolean.

## Quality Priority

A ranked mapping defining preference order (highest first):

```perl
my %QUALITY_RANK = (
    MEDIA_TAG_ATMOS => 3,  # [A] - Dolby Atmos
    MEDIA_TAG_MAX   => 2,  # [M] - HiRes DASH
    MEDIA_TAG_HIGH  => 1,  # [H] - CD lossless
);
```

Only enabled tiers participate:
- `[A]` requires `enableAtmos` pref to be true, otherwise rank 0 (excluded)
- `[M]` requires `enableDASH` pref to be true, otherwise rank 0 (excluded)
- `[H]` is always eligible (rank 1)

## Identity Fingerprint

What makes two albums "the same album in different quality":

```
artist_id : title : numberOfTracks
```

Quality tag and explicit flag are excluded from the fingerprint. Those are selection criteria applied after grouping.

## Pipeline

### Step 1: `_tagAlbums(\@albums)` -> \@tagged

Annotate and filter.

For each album in the input list:
1. Call `getMediaInfo($album)` once, attach result as `$album->{_media_info}`
2. Compute quality rank based on the media tag and enabled prefs
3. Skip albums with rank 0 (disabled tier) and albums without a LOSSLESS or DOLBY_ATMOS tag
4. Attach `_quality_rank` (integer) and `_fingerprint` (identity string)

Returns: arrayref of annotated albums with disabled tiers removed.

### Step 2: `_selectPreferred(\@tagged)` -> \@selected

Group and pick best quality.

1. Group albums by `_fingerprint`
2. Within each group, find the maximum `_quality_rank`
3. Keep only albums at the maximum rank (may be 2: explicit + clean at same quality)
4. Discard lower-quality duplicates

Returns: arrayref with at most 2 albums per identity (explicit and clean variants at best available quality).

### Step 3: `_filterExplicit(\@selected, $preferExplicit)` -> \@final

Pick explicit/clean winner.

1. Group by `_fingerprint`
2. If group has only one album, keep it regardless
3. If group has both explicit and clean:
   - `$preferExplicit` true: keep explicit
   - `$preferExplicit` false: keep clean

Returns: arrayref with exactly one album per identity.

## Data Flow

```
TIDAL API response (N albums, many duplicates)
  |
  v
_tagAlbums: annotate with quality rank + fingerprint, drop disabled tiers
  |  (N' albums, each with _quality_rank, _fingerprint, _media_info)
  v
_selectPreferred: group by fingerprint, keep only best quality tier
  |  (M albums, <=2 per identity: explicit + clean at same quality)
  v
_filterExplicit: pick explicit/clean winner per group
  |  (K albums, 1 per identity)
  v
returned to caller
```

## Preference Changes

### Removed
- `enableDASHPreferHiRes` -- the new algorithm always picks the highest available enabled quality tier; this pref is redundant
- `explicitAlbumHandling` -- 3-way per-user hash, replaced by simpler boolean

### Added/Changed
- `preferExplicit` -- boolean (default 0). True = prefer explicit versions when both exist.

### Migration
- `$prefs->migrate(3, sub { ... })` in Plugin.pm
- Convert `explicitAlbumHandling` values: 0 or 2 -> `preferExplicit => 0`, 1 -> `preferExplicit => 1`
- Remove `enableDASHPreferHiRes` from prefs
- Update `Settings.pm` prefs list and `settings.html` to remove the prefer HiRes checkbox and replace the 3-way explicit dropdown with a checkbox

## Files Changed

| File | Change |
|------|--------|
| `API/Async.pm` | Replace `_filterAlbums` with 3 named subs |
| `Plugin.pm` | Add `$prefs->migrate(3, ...)`, update `$prefs->init`, remove `enableDASHPreferHiRes` |
| `Settings.pm` | Remove `enableDASHPreferHiRes` from prefs list, replace `explicitAlbumHandling` handling |
| `settings.html` | Remove prefer HiRes checkbox, replace explicit dropdown with checkbox |
| `strings.txt` | Add/update string for `preferExplicit`, remove `SUPPORT_DASH_PREFER_HIRES` strings |

## What's Preserved

- The LOSSLESS tag check on `mediaMetadata.tags` (gates whether an album is streamable at all)
- The DOLBY_ATMOS tag check gated by `enableAtmos` pref
- The overall contract: input is a list of album items from TIDAL API, output is a deduplicated filtered list

## Testing

No automated test infrastructure exists. Verification is manual:
1. With DASH disabled: only `[H]` albums appear, no duplicates
2. With DASH enabled: `[M]` albums preferred over `[H]` for same identity
3. With Atmos enabled: `[A]` albums preferred over `[M]` and `[H]`
4. Explicit handling: toggling `preferExplicit` correctly picks the right version
5. Fallback: if only clean version exists at best quality, it shows regardless of explicit pref
