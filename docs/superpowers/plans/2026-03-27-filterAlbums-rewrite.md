# _filterAlbums Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the tangled `_filterAlbums` in `API/Async.pm` with a 3-step pipeline (tag, select, filter) and simplify preference handling.

**Architecture:** Three named subs each doing one thing — `_tagAlbums` annotates and drops disabled tiers, `_selectPreferred` groups by identity and keeps best quality, `_filterExplicit` picks explicit/clean winner. Prefs simplified: remove `enableDASHPreferHiRes` and `explicitAlbumHandling`, add `preferExplicit` boolean.

**Tech Stack:** Perl, Slim::Utils::Prefs, LMS Template Toolkit

---

### Task 1: Add preference migration and update defaults

**Files:**
- Modify: `Plugin.pm:26-50`

- [ ] **Step 1: Add migration 3 after migration 2**

After the existing `$prefs->migrate(2, ...)` block (line 34), add:

```perl
$prefs->migrate(3, sub {
	# Convert explicitAlbumHandling (3-way per-user hash) to preferExplicit (boolean)
	my $explicitAlbumHandling = $prefs->get('explicitAlbumHandling') || {};
	# If any account had "prefer explicit" (value 1), set global preferExplicit
	my $preferExplicit = 0;
	for my $val (values %$explicitAlbumHandling) {
		if ($val && $val == 1) {
			$preferExplicit = 1;
			last;
		}
	}
	$prefs->set('preferExplicit', $preferExplicit);
	$prefs->remove('explicitAlbumHandling');
	$prefs->remove('enableDASHPreferHiRes');
	1;
});
```

- [ ] **Step 2: Update $prefs->init to remove enableDASHPreferHiRes**

Change the `$prefs->init` block to remove `enableDASHPreferHiRes`:

```perl
$prefs->init({
	quality => 'HIGH',
	preferExplicit => 0,
	countryCode => '',
	enableCustomClientIDSecret => 0,
	custom_cid => '',
	custom_sec => '',
	enableDASH => 0,
	enableDASHStream => 0,
	enableAtmos => 0,
});
```

- [ ] **Step 3: Commit**

```
git add Plugin.pm
git commit -m "Task 1: Add pref migration 3, remove enableDASHPreferHiRes

Migrate explicitAlbumHandling (3-way per-user hash) to preferExplicit
(boolean). Remove enableDASHPreferHiRes — the new algorithm always
picks the highest available quality tier.

Part of #9"
```

---

### Task 2: Replace _filterAlbums with pipeline in Async.pm

**Files:**
- Modify: `API/Async.pm:11,154-213`

- [ ] **Step 1: Add `max` to List::Util import**

Change line 11 from:

```perl
use List::Util qw(min maxstr reduce);
```

to:

```perl
use List::Util qw(min max maxstr reduce);
```

- [ ] **Step 2: Replace _filterAlbums with the 3 new subs**

Delete the entire `_filterAlbums` sub (lines 154-213) and replace with:

```perl
sub _filterAlbums {
	my ($self, $albums) = @_;

	my $tagged = _tagAlbums($albums);
	my $selected = _selectPreferred($tagged);
	my $preferExplicit = $prefs->get('preferExplicit') || 0;
	return _filterExplicit($selected, $preferExplicit);
}

# Annotate albums with quality rank and identity fingerprint.
# Drop albums whose quality tier is disabled or that lack a LOSSLESS/DOLBY_ATMOS tag.
sub _tagAlbums {
	my ($albums) = @_;

	my $enableAtmos = $prefs->get('enableAtmos');
	my $enableDASH = $prefs->get('enableDASH');

	my @tagged;
	for my $album (@{$albums || []}) {
		my @tags = @{$album->{mediaMetadata}->{tags} || []};

		# Must have LOSSLESS or DOLBY_ATMOS tag to be streamable at lossless tier
		next unless grep { /^LOSSLESS$/ || /^DOLBY_ATMOS$/ } @tags;

		my $info = Plugins::TIDAL::API::getMediaInfo($album);
		my $tag = $info->{media_tag};

		# Compute quality rank; 0 means tier is disabled
		my $rank = 0;
		if ($tag eq MEDIA_TAG_ATMOS && $enableAtmos) {
			$rank = 3;
		}
		elsif ($tag eq MEDIA_TAG_MAX && $enableDASH) {
			$rank = 2;
		}
		elsif ($tag eq MEDIA_TAG_HIGH) {
			$rank = 1;
		}

		next unless $rank;

		$album->{_media_info} = $info;
		$album->{_quality_rank} = $rank;
		$album->{_fingerprint} = join(':', $album->{artist}->{id}, $album->{title}, $album->{numberOfTracks});

		push @tagged, $album;
	}

	return \@tagged;
}

# Group by identity fingerprint, keep only albums at the highest available quality rank.
# May return up to 2 per identity (explicit + clean at same quality).
sub _selectPreferred {
	my ($tagged) = @_;

	# Group by fingerprint
	my %groups;
	for my $album (@$tagged) {
		push @{$groups{$album->{_fingerprint}}}, $album;
	}

	# From each group, keep only albums at the best quality rank
	my @selected;
	for my $fp (keys %groups) {
		my $group = $groups{$fp};
		my $best_rank = max(map { $_->{_quality_rank} } @$group);
		push @selected, grep { $_->{_quality_rank} == $best_rank } @$group;
	}

	return \@selected;
}

# Pick explicit/clean winner from each fingerprint group.
# Returns exactly one album per identity.
sub _filterExplicit {
	my ($selected, $preferExplicit) = @_;

	my %groups;
	for my $album (@$selected) {
		push @{$groups{$album->{_fingerprint}}}, $album;
	}

	my @final;
	for my $fp (keys %groups) {
		my $group = $groups{$fp};

		if (scalar @$group == 1) {
			push @final, $group->[0];
			next;
		}

		# Multiple versions exist — pick based on preference
		my ($explicit) = grep { $_->{explicit} } @$group;
		my ($clean) = grep { !$_->{explicit} } @$group;

		if ($preferExplicit && $explicit) {
			push @final, $explicit;
		}
		elsif (!$preferExplicit && $clean) {
			push @final, $clean;
		}
		else {
			# Fallback: take whatever exists
			push @final, $group->[0];
		}
	}

	return \@final;
}
```

- [ ] **Step 3: Verify no other code references enableDASHPreferHiRes in Async.pm**

Run: `grep -n 'enableDASHPreferHiRes' API/Async.pm`
Expected: no matches (the old code that referenced it was in the deleted `_filterAlbums`)

- [ ] **Step 4: Commit**

```
git add API/Async.pm
git commit -m "Task 2: Replace _filterAlbums with Group-Select-Filter pipeline

Three named subs replace the tangled grep/map:
- _tagAlbums: annotate + drop disabled tiers
- _selectPreferred: group by identity, keep best quality
- _filterExplicit: pick explicit/clean winner

Each sub does one thing with clear inputs and outputs.
No mutable state shared across closures.

Closes #9"
```

---

### Task 3: Update Settings.pm to remove old prefs and add preferExplicit

**Files:**
- Modify: `Settings.pm:19,36-49,68-69`

- [ ] **Step 1: Update prefs list**

Change line 19 from:

```perl
sub prefs { return ($prefs, qw(quality countryCode enableCustomClientIDSecret custom_cid custom_sec enableDASH enableDASHPreferHiRes enableDASHStream enableAtmos)) }
```

to:

```perl
sub prefs { return ($prefs, qw(quality countryCode enableCustomClientIDSecret custom_cid custom_sec enableDASH enableDASHStream enableAtmos preferExplicit)) }
```

- [ ] **Step 2: Remove explicitAlbumHandling from handler**

Replace the `if ($params->{saveSettings})` block (lines 36-49) with:

```perl
	if ($params->{saveSettings}) {
		my $dontImportAccounts = $prefs->get('dontImportAccounts') || {};
		foreach my $prefName (keys %$params) {
			if ($prefName =~ /^pref_dontimport_(.*)/) {
				$dontImportAccounts->{$1} = $params->{$prefName};
			}
		}
		$prefs->set('dontImportAccounts', $dontImportAccounts);
	}
```

- [ ] **Step 3: Remove explicitAlbumHandling from beforeRender**

Replace the `beforeRender` sub (lines 54-70) with:

```perl
sub beforeRender {
	my ($class, $params) = @_;

	my $accounts = $prefs->get('accounts') || {};

	$params->{credentials} = [ sort {
		$a->{name} cmp $b->{name}
	} map {
		{
			name => Plugins::TIDAL::API->getHumanReadableName($_),
			id => $_->{userId},
		}
	} values %$accounts] if scalar keys %$accounts;

	$params->{dontImportAccounts} = $prefs->get('dontImportAccounts') || {};
}
```

- [ ] **Step 4: Commit**

```
git add Settings.pm
git commit -m "Task 3: Remove explicitAlbumHandling and enableDASHPreferHiRes from Settings

Replace per-user 3-way explicit handling with global preferExplicit
boolean. Remove enableDASHPreferHiRes from prefs list.

Part of #9"
```

---

### Task 4: Update settings.html — remove prefer HiRes, simplify explicit UI

**Files:**
- Modify: `HTML/EN/plugins/TIDAL/settings.html`

- [ ] **Step 1: Replace the per-account explicit dropdown with a global preferExplicit checkbox**

In the account table header row (line 8), remove the explicit albums column:

```html
			<tr>
				<th>[% "PLUGIN_TIDAL_ACCOUNT" | string %][% "COLON" | string %]</th>
				<th>[% "PLUGIN_TIDAL_IMPORT_LIBRARY"| string %][% "COLON" | string %]</th>
				<th></th>
			</tr>
```

In each account row (lines 11-32), remove the explicit dropdown `<td>` block (lines 21-26). The resulting row template:

```html
		[% FOREACH creds = credentials %]
			[% accountName = creds.name; accountId = creds.id %]
			<tr>
				<td style="vertical-align: middle; padding-right: 10px">[% accountName | html %]</td>
				<td style="vertical-align: middle; padding-right: 10px">
					<select class="stdedit" name="pref_dontimport_[% accountId %]">
						<option [% IF !dontImportAccounts.$accountId %]selected [% END %]value="0">[% "YES"| string %]</option>
						<option [% IF dontImportAccounts.$accountId %]selected [% END %]value="1">[% "NO" | string %]</option>
					</select>
				</td>
				<td style="vertical-align: middle">
					<input name="delete_[% accountId %]" type="submit" value="[% "DELETE" | string %]" class="stdclick" />
				</td>
			</tr>
		[% END %]
```

Then add a global preferExplicit checkbox after the country code setting (after line 50), before the `<hr>`:

```html
	[% WRAPPER setting title="PLUGIN_TIDAL_PREFER_EXPLICIT" desc="PLUGIN_TIDAL_PREFER_EXPLICIT_DESC" %]
		<input type="checkbox" name="pref_preferExplicit" id="preferExplicit" [% IF
			prefs.pref_preferExplicit %]checked="checked" [% END %] value="1" class="stdedit" />
	[% END %]
```

- [ ] **Step 2: Remove the prefer HiRes checkbox**

Delete the `settingGroup` block containing `enableDASHPreferHiRes` (lines 74-87). Keep `enableDASHStream` but move it into its own `WRAPPER setting` block:

```html
	[% WRAPPER setting title="PLUGIN_TIDAL_EXPERIMENTAL_SUPPORT_DASH_STREAM" desc="PLUGIN_TIDAL_EXPERIMENTAL_SUPPORT_DASH_STREAM_DESC" %]
		<input type="checkbox" name="pref_enableDASHStream" id="enableDASHStream" [% IF
			prefs.pref_enableDASHStream %]checked="checked" [% END %] value="1" class="stdedit" />
	[% END %]
```

- [ ] **Step 3: Commit**

```
git add HTML/EN/plugins/TIDAL/settings.html
git commit -m "Task 4: Simplify settings UI — global explicit checkbox, remove prefer HiRes

Replace per-account 3-way explicit dropdown with a single global
preferExplicit checkbox. Remove enableDASHPreferHiRes checkbox.
Move enableDASHStream to its own setting block.

Part of #9"
```

---

### Task 5: Update strings.txt

**Files:**
- Modify: `strings.txt`

- [ ] **Step 1: Add preferExplicit strings and remove prefer HiRes strings**

After the existing `PLUGIN_TIDAL_SHOW_ALL` block (around line 358), add:

```
PLUGIN_TIDAL_PREFER_EXPLICIT
	EN	Prefer explicit versions

PLUGIN_TIDAL_PREFER_EXPLICIT_DESC
	EN	When both explicit and clean versions of an album are available, prefer the explicit version
```

Delete the `PLUGIN_TIDAL_EXPERIMENTAL_SUPPORT_DASH_PREFER_HIRES` block (lines 390-391) and the `PLUGIN_TIDAL_EXPERIMENTAL_SUPPORT_DASH_PREFER_HIRES_DESC` block (lines 393-394).

- [ ] **Step 2: Commit**

```
git add strings.txt
git commit -m "Task 5: Add preferExplicit strings, remove prefer HiRes strings

Part of #9"
```

---

### Task 6: Manual verification

No automated tests exist. Verify manually.

- [ ] **Step 1: Verify no remaining references to removed prefs**

Run:
```
grep -rn 'enableDASHPreferHiRes' *.pm API/*.pm
grep -rn 'explicitAlbumHandling' *.pm API/*.pm Settings.pm
```
Expected: no matches for either.

- [ ] **Step 2: Verify no remaining references in HTML/strings**

Run:
```
grep -rn 'enableDASHPreferHiRes' HTML/ strings.txt
grep -rn 'explicitAlbumHandling' HTML/ strings.txt
```
Expected: no matches.

- [ ] **Step 3: Verify _filterAlbums caller is unchanged**

Run: `grep -n '_filterAlbums' API/Async.pm`
Expected: two matches — the call in `artistAlbums` (line ~120) and the sub definition.

- [ ] **Step 4: Final commit if any cleanup needed**

If any stray references found, fix and commit.
