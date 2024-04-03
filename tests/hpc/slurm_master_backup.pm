# SUSE's openQA tests
#
# Copyright 2017-2018 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: slurm cluster initialization
# Maintainer: Kernel QE <kernel-qa@suse.de>

use Mojo::Base 'hpcbase', -signatures;
use testapi;
use serial_terminal 'select_serial_terminal';
use lockapi;
use utils;
use hpc::utils 'get_slurm_version';

sub run ($self) {
    select_serial_terminal();
    my $nodes = get_required_var("CLUSTER_NODES");
    my $slurm_pkg = get_slurm_version(get_var('SLURM_VERSION', ''));

    barrier_wait('CLUSTER_PROVISIONED');

    $self->prepare_user_and_group();
    zypper_call("in $slurm_pkg $slurm_pkg-munge");

    $self->mount_nfs();
    barrier_wait("SLURM_SETUP_DONE");
    barrier_wait('SLURM_SETUP_DBD');
    barrier_wait("SLURM_MASTER_SERVICE_ENABLED");

    # enable and start munge
    $self->enable_and_start('munge');

    # Install mrsh and mrsh-server to allow t10 basic
    zypper_call('in mrsh mrsh-server');
    $self->enable_and_start('mrlogind.socket mrshd.socket');

    # enable and start slurmctld
    $self->enable_and_start('slurmctld');
    systemctl 'status slurmctld';

    # enable and start slurmd since maester also acts as Node here
    $self->enable_and_start('slurmd');
    systemctl 'status slurmd';

    assert_script_run("srun -N ${nodes} /bin/ls");
    assert_script_run("sinfo -N -l");
    assert_script_run("scontrol ping");

    barrier_wait("SLURM_SLAVE_SERVICE_ENABLED");
    barrier_wait("SLURM_MASTER_RUN_TESTS");
}

sub test_flags ($self) {
    return {fatal => 1, milestone => 1};
}

sub post_fail_hook ($self) {
    $self->destroy_test_barriers();
    select_serial_terminal;
    $self->upload_service_log('slurmd');
    $self->upload_service_log('munge');
    $self->upload_service_log('slurmctld');
    upload_logs('/var/log/slurmctld.log', failok => 1);
}

1;
