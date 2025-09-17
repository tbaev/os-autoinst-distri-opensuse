# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Helper class for google connection and authentication
#
# Maintainer: qa-c team <qa-c@suse.de>

package publiccloud::gcp_client;
use Mojo::Base -base;
use testapi;
use utils;
use version_utils 'is_sle';
use publiccloud::utils;
use Mojo::Util qw(b64_decode);
use Mojo::JSON 'decode_json';
use mmapi 'get_current_job_id';

use constant CREDENTIALS_FILE => '/root/google_credentials.json';

has storage_name => sub { get_var('PUBLIC_CLOUD_STORAGE_ACCOUNT', 'openqa-storage') };
has project_id => sub { get_var('PUBLIC_CLOUD_GOOGLE_PROJECT_ID') };
has account => sub { get_var('PUBLIC_CLOUD_GOOGLE_ACCOUNT') };
has gcr_zone => sub { get_var('PUBLIC_CLOUD_GCR_ZONE', 'eu.gcr.io') };
has region => sub { get_required_var('PUBLIC_CLOUD_REGION') };
has availability_zone => sub { get_required_var('PUBLIC_CLOUD_AVAILABILITY_ZONE') };
has username => sub { get_var('PUBLIC_CLOUD_USER', 'susetest') };

sub init {
    my ($self) = @_;
    my $data = get_credentials(url_suffix => 'gce.json', output_json => CREDENTIALS_FILE);
    $self->project_id($data->{project_id});
    $self->account($data->{client_id});
    assert_script_run('source ~/.bashrc');
    systemctl('stop chronyd.service');
    script_retry("chronyd -q 'pool time.google.com iburst'", retry => 5, delay => 30);
    assert_script_run('gcloud config set account ' . $self->account);
    assert_script_run(
        'gcloud auth activate-service-account --key-file=' . CREDENTIALS_FILE . ' --project=' . $self->project_id);
}

sub get_credentials_file_name {
    return CREDENTIALS_FILE;
}


=head2 get_container_registry_prefix

Get the full registry prefix URL for any containers image registry of ECR based on the account and region
=cut

sub get_container_registry_prefix {
    my ($self) = @_;
    return $self->gcr_zone . '/' . $self->project_id;
}

=head2 get_container_image_full_name

Get the full name for a container image in ECR registry
=cut

sub get_container_image_full_name {
    my ($self, $tag) = @_;
    my $full_name_prefix = $self->get_container_registry_prefix();
    return "$full_name_prefix/$tag" . get_current_job_id() . ":latest";
}

=head2 configure_podman

Configure the podman to access the cloud provider registry
=cut

sub configure_podman {
    my ($self) = @_;
    assert_script_run('gcloud auth configure-docker --quiet ' . $self->gcr_zone);
}

1;
