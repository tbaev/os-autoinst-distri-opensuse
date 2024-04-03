# Copyright 2015-2019 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package db_utils;

use base 'Exporter';

use strict;
use warnings;
use testapi;
use mmapi qw(get_current_job_id);
use JSON qw(encode_json);

our @EXPORT = qw(
  influxdb_push_data
  influxdb_read_data
  push_image_data_to_db
  check_postgres_db
  is_ok_url
);

sub build_influx_kv {
    my $hash = shift;
    my $req = '';
    for my $k (keys(%{$hash})) {
        my $v = $hash->{$k};
        $v =~ s/,/\\,/g;
        $v =~ s/ /\\ /g;
        $v =~ s/=/\\=/g;
        $req .= $k . '=' . $v . ',';
    }
    return substr($req, 0, -1);
}

sub build_influx_query {
    my $data = shift;
    my $req = $data->{table} . ',';
    $req .= build_influx_kv($data->{tags});
    $req .= ' ';
    $req .= build_influx_kv($data->{values});
    return $req;
}

=head2 influxdb_push_data

    influxdb_push_data($url, $db, $org, $token, $data [, quiet => 1] [, proceed_on_failure => 1])

Builds an influx-db query and write it to the given database specified with
C<url>, C<org> and C<db> for the Influx DB organization and database name.
C<token> is used for user authentication.
C<quiet> is a boolean flag to hide output results, default true.
C<proceed_on_failure> is a boolean flag to continue and not die when return_code not ok, default false.
C<data> is a hash containing the table name in Influx DB, the tags and the values to plot.

Return code: 
    1, when ok and data uploaded to remote db
    undef or die, when push failed 

Example of data:
    $data = {
        table  => 'my_db_table_name',
        tags   => { BUILD => '42', KERNEL => '4.12.14-lp151.28.20-default'},
        values => { io_reads' => 1337, io_writes => 1338 }
    }
=cut

sub influxdb_push_data {
    my ($url, $db, $org, $token, $data, %args) = @_;
    $args{quiet} //= 1;
    $args{proceed_on_failure} //= 0;
    $data = build_influx_query($data);
    my $cmd = sprintf("curl -iLk -X POST '$url/api/v2/write?org=$org&bucket=$db' --header 'Authorization: Token $token' --write-out 'RETURN_CODE:%%{response_code}' --data-binary '%s'", $data);
    # Hide the token in the info box
    my $out = $cmd;
    $out =~ s/$token/<redacted>/;
    record_info('curl POST', $out);

    my $output = script_output($cmd, quiet => $args{quiet}, proceed_on_failure => $args{proceed_on_failure});
    my ($return_code) = $output =~ /RETURN_CODE:(\d+)/;
    unless ($return_code >= 200 && $return_code < 300) {
        my $msg = "Failed pushing data into Influx DB:\n$output\n";
        record_info("FAIL push db", $msg, result => 'fail') if ($args{proceed_on_failure});
        die($msg) unless ($args{proceed_on_failure});
        return;
    }
    return 1;
}

=head2 influxdb_read_data

Builds an Influx DB query and read data from specified database
with C<url_base>, C<db> and C<org> for the Influx DB name.
C<token> contains the access token.
C<query> contains SELECT query for given DB.

returns json with results of SELECT query.

=cut

sub influxdb_read_data {
    my ($url_base, $db, $org, $token, $query) = @_;

    my $ua = Mojo::UserAgent->new();
    $ua->max_redirects(5);

    my $mojo_url = Mojo::URL->new("$url_base/query");
    $mojo_url->query(orgID => $org, db => $db, q => $query);
    my $res = $ua->post($mojo_url => {Authorization => "Token $token", Accept => "application/json", 'Content-type' => "application/json"})->res;
    if ($res->code != 200) {
        die sprintf("Failed to get data from InfluxDB. \n Response code : %s \n Message: %s \n", $res->code, $res->message);
    } else {
        my $json = $res->json;
        my @results = $json->{results};
        # Check if we got an error object as reply
        my $result = $results[0][0];
        if (defined($result->{error})) {
            die($result->{error});
        }
        return $json;
    }
}



=head2 push_image_data_to_db

Pushes data to specified with C<url> and C<db> for the Postgres DB name using curl.

=cut

sub push_image_data_to_db {
    my ($product, $image, $value, %args) = @_;
    my $db_log = "/tmp/db.log";
    my $db_ip = get_required_var('POSTGRES_IP');
    my $db_port = get_var('POSTGRES_PORT', '5444');
    my $token = get_required_var('_SECRET_DATABASE_PWD');

    my $openqa_host = get_required_var('OPENQA_HOSTNAME');
    my $job_url;
    my $job_id = get_current_job_id();
    if ($openqa_host =~ /openqa1-opensuse|openqa.opensuse.org/) {    # O3 hostname
        $job_url = 'https://openqa.opensuse.org/tests/' . $job_id;
    }
    elsif ($openqa_host =~ /openqa.suse.de/) {    # OSD hostname
        $job_url = 'https://openqa.suse.de/tests/' . $job_id;
    } else {
        $job_url = $openqa_host . '/' . $job_id;
    }
    bmwqemu::diag('job_url', $job_url);
    return 0 unless ($job_url);

    $args{distri} //= get_required_var('DISTRI');
    $args{version} //= get_required_var('VERSION');
    $args{arch} //= get_required_var('ARCH');
    $args{flavor} //= get_required_var('FLAVOR');
    $args{build} //= get_required_var('BUILD');
    $args{table} //= 'size';
    $args{url} = $job_url;
    $args{asset} = $image;
    $args{value} = $value;
    $args{product} = $product;
    $args{build} =~ s/\_.*//;    #To remove unneeded strings, e.g. 15.11_init-image -> 15.11

    my $ua = Mojo::UserAgent->new;
    $ua = $ua->max_connections(5);
    $ua = $ua->max_redirects(3);
    $ua = $ua->connect_timeout(30);

    my $url = sprintf('http://%s:%s/%s', $db_ip, $db_port, $args{table});
    bmwqemu::diag("Database URL: $url");
    my $table = delete $args{table};

    #my $data = encode_json(\%args);
    bmwqemu::diag("Collected image data: " . encode_json(\%args));

    my $res = $ua->post("$url" => {Authorization => "Bearer $token", Accept => "application/json",
            'Content-type' => "application/json"} => json => \%args)->result();

    # if successful push, it should return 'HTTP/1.1 201 Created'
    if ($res->code == 201) {
        bmwqemu::diag("Image data has been successfully pushed to the Database ($table), RC => " . $res->code);
    } elsif ($res->code == 409) {
        bmwqemu::diag("This image info already exists in $table, RC => " . $res->code);
        # return to the caller that conflict has been found
        # caller should exit the test case module immediately
    } else {
        record_info('DB error', "There has been a problem pushing data to the $table. RC => " . $res->code, result => 'softfail');
    }

    return $res->code;
}

sub check_postgres_db {
    my $image = shift;
    my $db_ip = get_var('POSTGRES_IP');
    my $db_port = get_var('POSTGRES_PORT', '5444');
    my $db_db = get_var('POSTGRES_DB', 'size');
    my $db_log = "/tmp/db.log";

    ## We only allow data push to the database if all of the following conditions are met:
    ## 1. The job must hold the POSTGRES_IP setting (database host)
    ## 2. The job shouldn't be a verification run
    ## 3. The job must be executed from OSD or O3

    ## Check if database host ist set
    return 0 unless ($db_ip);

    ## Check if job is a verification run
    # CASEDIR var is always set (check vars.json). If not explicitly specified, the value is "sle/sle-micro" for OSD and "opensuse/leap-micro" for O3
    return 0 if (get_required_var('CASEDIR') !~ m/^sle$|^opensuse$|^(sle|leap)-micro$/);

    ## Check if job is executed on OSD/O3
    my $job_url;
    my $openqa_host = get_required_var('OPENQA_HOSTNAME');
    if ($openqa_host =~ /openqa1-opensuse|openqa.opensuse.org/) {    # O3 hostname
        $job_url = 'https://openqa.opensuse.org/tests/' . get_current_job_id();
    } elsif ($openqa_host =~ /openqa.suse.de/) {    # OSD hostname
        $job_url = 'https://openqa.suse.de/tests/' . get_current_job_id();
    } else {
        return 0;
    }

    ## Probe the database
    # A successful query should return 'HTTP/1.1 200 OK'
    # Empty records will return  '{"results":[{"statement_id":0}]}'
    # Existing records will return '{"results":[{"statement_id":0,"series":[{"name":"size","columns":["time","value"],"values"' ...
    my $request = "curl -IfLv 'http://$db_ip:$db_port/$db_db'";
    if (script_run("$request 2>&1 >/var/tmp/db_curl.tmp", timeout => 120, die_on_timeout => 0) != 0) {
        my $output = script_output("cat /var/tmp/db_curl.tmp");
        record_info("db error", "cannot reach POSTGREST database\n$request\n$output", result => 'fail');
        return 0;
    }
    return 1;
}

sub is_ok_url {
    # url connectivity check
    # Parameters: url[:port] [, timeout: default=90]
    my ($url, %args) = @_;
    $args{timeout} //= 120;
    my $cmd = "curl -skf --connect-timeout " . $args{timeout} . " " . $url . " >/dev/null";
    # t+3 to let curl trigger first.
    return (script_run($cmd, timeout => ($args{timeout} + 3), die_on_timeout => 0) == 0);
}
