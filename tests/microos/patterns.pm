# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Smoke pattern installation check
# Maintainer: QA-c Team <qa-c@suse.de>

use Mojo::Base qw(consoletest);
use testapi;
use transactional qw(trup_call process_reboot);
use utils qw(zypper_call);
use serial_terminal qw(select_serial_terminal);
use version_utils qw(is_sle_micro);

sub run {
    shift->select_serial_terminal();

    # display all patterns
    record_info('patterns', script_output 'zypper se -t pattern');

    # collect available not yet installed patterns
    my @available_patterns = split(/\n/, script_output "zypper -q se -t pattern -u");
    my @patterns = map { m/\|\s+(.*?)\s+\|.*pattern$/ } @available_patterns;

    # install new patterns
    my @inst_patterns = @patterns;
    trup_call('pkg install -t pattern ' . join(" ", @inst_patterns), timeout => 720);
    process_reboot(trigger => 1);

    # expect empty list therefore ZYPPER_EXIT_INF_CAP_NOT_FOUND
    # skip the check below on slem6.0 due to bsc#1219200
    zypper_call "-q se -t pattern -u", exitcode => [104] unless is_sle_micro('>=6.0');
}

sub post_fail_hook {
    select_console 'log-console';

    upload_logs '/var/log/zypper.log';
    upload_logs '/var/log/zypp/history';
}

1;
