#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 8;

use lib 't/lib';
use MockLMS;

# Prefs
my $prefs = Slim::Utils::Prefs::preferences('plugin.tidal');
ok($prefs, 'preferences() returns object');

$prefs->set('quality', 'LOSSLESS');
is($prefs->get('quality'), 'LOSSLESS', 'prefs get/set works');

$prefs->remove('quality');
is($prefs->get('quality'), undef, 'prefs remove works');

# Cache
my $cache = Slim::Utils::Cache->new();
ok($cache, 'Cache->new returns object');

$cache->set('key1', 'val1', 3600);
is($cache->get('key1'), 'val1', 'cache get/set works');

$cache->remove('key1');
is($cache->get('key1'), undef, 'cache remove works');

# Logger
my $log = Slim::Utils::Log::logger('plugin.tidal');
ok($log, 'logger() returns object');
ok(!$log->is_debug, 'is_debug returns false');
