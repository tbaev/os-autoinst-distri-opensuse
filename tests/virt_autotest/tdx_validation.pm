# SUSE's openQA tests
#
# Copyright 2025 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Virtualization TDX guest verification test
# Supports: SLES 16+ host (guests: SLES 16+)
#
# Test description:
# This module tests whether TDX virtual machine has been successfully
# installed on TDX enabled physical host by checking support status
# on the host first and then on the virtual machine itself.
#
# Modes:
# - Maintenance update: ENABLE_TDX=1
# - Unified guest installation: VIRT_TDX_GUEST_INSTALL=1
#
# Maintainer: QE-Virtualization <qe-virt@suse.de> tbaev@suse.com

package tdx_validation;

use base 'virt_feature_test_base';
use POSIX 'strftime';
use File::Basename;
use testapi;
use IPC::Run;
use utils;
use virt_utils;
use virt_autotest::common;
use virt_autotest::utils;
use version_utils qw(is_sle is_tumbleweed is_alp);
use Utils::Architectures;

sub run_test {
    my $self = shift;

    record_info('TDX Test Started', 'TDX verification test started');
}

sub post_fail_hook {
    my $self = shift;

    record_info('Failure Hook', "Test failed, collecting logs for diagnosis");
}

1;
