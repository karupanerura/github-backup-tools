use strict;
use warnings;
use utf8;

use Pithub;
use Smart::Options::Declare;
use Path::Tiny qw/path/;
use JSON::PP;
use URI;

use DDP;
use Devel::KYTProf;

my $_JSON = JSON::PP->new->utf8->canonical->pretty;

opts_coerce 'Path::Tiny' => 'Str', \&path;
opts_coerce 'URI' => 'Str', sub { URI->new(@_)->canonical };

MAIN: {
    opts my $user      => 'Str',
         my $org       => 'Str',
         my $repos     => 'Multiple',
         my $with_wiki => 'Bool',
         my $git_host  => { isa => 'Str', default => 'github.com' },
         my $protocol  => { isa => 'Str', default => 'ssh' },
         my $ssh_user  => { isa => 'Str', default => 'git' },
         my $api_uri   => { isa => 'URI', default => 'https://api.github.com' },
         my $outdir    => { isa => 'Path::Tiny', default => './out' };

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
    my %repo_info;
    unless (@$repos) {
        my $result = $pithub->repos->list(
            $user ? (user => $user) : (),
            $org  ? (org  => $org)  : (),
        );

        my $owner = $user || $org;
        while (my $row = $result->next) {
            my $repo_name = "$owner/$row->{name}";
            $repo_info{$repo_name} = $row;
            push @$repos => $repo_name;
        }
    }

    $outdir->mkpath;
    for my $repo (@$repos) {
        my ($owner, $repo) = split m!\/!, $repo;

        my $url;
        if ($protocol eq 'ssh') {
            $url = sprintf 'ssh://%s@%s/%s/%s', $ssh_user, $git_host, $owner, $repo;
        } elsif ($protocol eq 'https') {
            $url = sprintf 'https://%s/%s/%s', $git_host, $owner, $repo;
        } elsif ($protocol eq 'git') {
            $url = sprintf 'git://%s/%s/%s', $git_host, $owner, $repo;
        }

        $outdir->child($owner)->mkpath;

        my $repodir = $outdir->child($owner)->child($repo);
        if ($repodir->exists) {
            my $exit_code = system 'git', '--work-tree', $repodir, '--git-dir', $repodir->child('.git'), 'pull';
            if ($exit_code != 0) {
                die "[ERROR] Failed to pull $repo";
            }
        } else {
            my $exit_code = system 'git', 'clone', "$url.git", $repodir;
            if ($exit_code != 0) {
                die "[ERROR] Failed to clone $repo";
            }
        }

        if ($with_wiki) {
            my $repo_info = $repo_info{$repo} ||= $pithub->repos->get(user => $owner, repo => $repo)->next;
            if ($repo_info->{has_wiki}) {
                my $repodir = $outdir->child($owner)->child("$repo.wiki");
                if ($repodir->exists) {
                    my $exit_code = system 'git', '--work-tree', $repodir, '--git-dir', $repodir->child('.git'), 'pull';
                    if ($exit_code != 0) {
                        die "[ERROR] Failed to pull $repo wiki";
                    }
                } else {
                    my $exit_code = system 'git', 'clone', "$url.wiki.git", $repodir;
                    if ($exit_code != 0) {
                        die "[ERROR] Failed to clone $repo wiki";
                    }
                }
            }
        }
    }
};
