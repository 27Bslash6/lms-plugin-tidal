#!/usr/bin/perl
use strict;

use XML::Simple;
use File::Basename;
use Digest::SHA;

my $repofile = $ARGV[0];
my $version = $ARGV[1];
my $zipfile = $ARGV[2];
my $url = $ARGV[3];

my $repo = XMLin($repofile, ForceArray => 1, KeepRoot => 0, KeyAttr => 0, NoAttr => 0);
$repo->{plugins}[0]->{plugin}[0]->{version} = $version;

open (my $fh, "<", $zipfile) or die $!;
binmode $fh;

my $sha1 = Digest::SHA->new('sha1');
$sha1->addfile($fh);
close $fh;

my $hexdigest = $sha1->hexdigest;
$repo->{plugins}[0]->{plugin}[0]->{sha}[0] = $hexdigest;
print("version:$version sha:$hexdigest\n");

$url .= "/$zipfile";
$repo->{plugins}[0]->{plugin}[0]->{url}[0] = $url;

XMLout($repo, RootName => 'extensions', NoSort => 1, XMLDecl => 1, KeyAttr => '', OutputFile => $repofile, NoAttr => 0);


