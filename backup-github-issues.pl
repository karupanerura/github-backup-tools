use strict;
use warnings;
use utf8;

use Pithub;
use Smart::Options::Declare;
use Path::Tiny qw/path/;
use JSON::PP;
use URI;
use URI::Escape qw/uri_escape_utf8/;

use DDP;
use Devel::KYTProf;

my $_JSON = JSON::PP->new->utf8->canonical->pretty;

opts_coerce 'Path::Tiny' => 'Str', \&path;
opts_coerce 'URI' => 'Str', sub { URI->new(@_)->canonical };

MAIN: {
    opts my $user    => 'Str',
         my $org     => 'Str',
         my $repos   => 'Multiple',
         my $api_uri => { isa => 'URI', default => 'https://api.github.com' },
         my $outdir  => { isa => 'Path::Tiny', default => './out' };

    my $pithub = do {
        my $token = $ENV{GITHUB_TOKEN}
            or die 'GITHUB_TOKEN environment variable is required';

        Pithub->new(token => $token, auto_pagination => 1, api_uri => $api_uri);
    };

    # validate opts
    if (!$user && !$org) {
        if (!@$repos) {
            die "Specify --user=xxx or --org=xxx or --repos=xxx,xxx";
        }
    } elsif ($user && $org) {
        die "Don't specify user and org both";
    }

    # fetch all repos
    unless (@$repos) {
        my $result = $pithub->repos->list(
            $user ? (user => $user) : (),
            $org  ? (org  => $org)  : (),
        );

        my $owner = $user || $org;
        while (my $row = $result->next) {
            push @$repos => "$owner/$row->{name}";
        }
    }

    for my $repo (@$repos) {
        my ($owner, $repo) = split m!\/!, $repo;

        {
            my $labels_dir = $outdir->child($owner)->child($repo)->child('labels');
            $labels_dir->mkpath;

            my $labels_result = $pithub->issues->labels->list(user => $owner, repo => $repo);
            while (my $row = $labels_result->next) {
                my $name = uri_escape_utf8($row->{name});
                $labels_dir->child("$name.json")->spew_raw($_JSON->encode($row));
            }
        };

        my $issues_dir = $outdir->child($owner)->child($repo)->child('issues');
        $issues_dir->mkpath;
        {
            my $issues_result = $pithub->issues->list(user => $owner, repo => $repo, params => {
                filter => 'all',
                state  => 'all',
            });
            while (my $row = $issues_result->next) {
                my $issue_id = $row->{number};

                $issues_dir->child("$issue_id.json")->spew_raw($_JSON->encode($row));
                $issues_dir->child($issue_id)->mkpath;
            }

            my $comments_result = $pithub->request(
                method => 'GET',
                path   => sprintf('/repos/%s/%s/issues/comments', $owner, $repo),
            );
            while (my $row = $comments_result->next) {
                my ($issue_id) = $row->{issue_url} =~ m!/([0-9]+)$!;
                my $comment_id = $row->{id};
                $issues_dir->child($issue_id)->child("issuecomment-${comment_id}.json")->spew_raw($_JSON->encode($row));
            }
        }

    }
};
