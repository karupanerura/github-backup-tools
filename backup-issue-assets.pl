use strict;
use warnings;
use utf8;

use Smart::Options::Declare;
use Path::Tiny qw/path/;
use Regexp::Common qw/URI/;
use JSON::PP;
use URI;
use LWP::Simple qw/mirror/;

use DDP;
use Devel::KYTProf;

my $_JSON = JSON::PP->new->utf8->canonical->pretty;

opts_coerce 'Path::Tiny' => 'Str', \&path;
opts_coerce 'URI' => 'Str', sub { URI->new(@_)->canonical };

my %BACKUP_TARGET = (
    '*.githubusercontent.com' => qr!.*!,
    'github.com'              => qr!^/files/!,
);

MAIN: {
    opts my $outdir  => { isa => 'Path::Tiny', default => './assets' };

    my @issue_files = @ARGV;
    unless (@issue_files) {
        die "Usage: $0 issues/1.json issues/2.json ...";
    }

    for my $issue_file (@issue_files) {
        my $issue = $_JSON->decode(path($issue_file)->slurp_raw);

        while ($issue->{body} =~ /\!\[.*?\]\($RE{URI}{-keep}\)/msg) {
            my $uri = URI->new($1);

            my $ok;
            for my $host_matcher (keys %BACKUP_TARGET) {
                my $path_matcher = $BACKUP_TARGET{$host_matcher};

                if ($host_matcher =~ s/^\*\.//) {
                    $ok = 1 if $uri->host =~ /\.\Q${host_matcher}\E$/ && $uri->path =~ $path_matcher;
                } elsif ($host_matcher eq $uri->host && $uri->path =~ $path_matcher) {
                    $ok = 1;
                }
                last if $ok;
            }
            next unless $ok;

            my $file_path = $outdir->child($uri->host)->child($uri->path);
            next if $file_path->exists;

            $file_path->parent->mkpath;
            mirror($uri, $file_path);
        }
    }
};
